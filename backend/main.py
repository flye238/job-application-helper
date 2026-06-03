# ==============================================================================
# Job Application Helper - FastAPI Backend
# ==============================================================================

import os
import re
import logging
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from openai import OpenAI
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Job Application Helper")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ------------------------------------------------------------------------------
# Request model
# ------------------------------------------------------------------------------

class JobRequest(BaseModel):
    job_description: str

# ------------------------------------------------------------------------------
# Key Vault helper
# ------------------------------------------------------------------------------

def get_openai_client() -> OpenAI:
    key_vault_uri = os.environ.get("KEY_VAULT_URI")
    if not key_vault_uri:
        raise RuntimeError("KEY_VAULT_URI environment variable not set.")
    credential = ManagedIdentityCredential()
    secret_client = SecretClient(vault_url=key_vault_uri, credential=credential)
    api_key = secret_client.get_secret("openai-api-key").value
    return OpenAI(api_key=api_key)

# ------------------------------------------------------------------------------
# Input sanitization
# ------------------------------------------------------------------------------

def sanitize_input(text: str, max_length: int = 5000) -> str:
    text = text.strip()
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)
    return text[:max_length]

# ------------------------------------------------------------------------------
# Prompt builder
# ------------------------------------------------------------------------------

def build_prompt(job_description: str) -> str:
    return f"""You are an expert career coach and professional resume writer.

A user has provided the following job description:

---
{job_description}
---

Please analyze the job description and provide the following three sections.
Use clear section headers exactly as shown below.

## COVER LETTER
Write a professional, compelling cover letter tailored to this job description.
Keep it to 3-4 paragraphs. Do not include placeholder text like [Your Name].

## INTERVIEW QUESTIONS
List 8 likely interview questions the hiring manager might ask based on this
job description. For each question, provide a brief 1-2 sentence tip on how
to approach the answer.

## SKILLS GAP ANALYSIS
Identify the top 5 skills or qualifications emphasized in the job description.
For each, rate how commonly candidates lack this skill (High / Medium / Low gap)
and provide one actionable suggestion for how to develop or demonstrate it.
"""

# ------------------------------------------------------------------------------
# Section parser
# ------------------------------------------------------------------------------

def parse_sections(text: str) -> dict:
    sections = {}
    pattern = r"##\s+(COVER LETTER|INTERVIEW QUESTIONS|SKILLS GAP ANALYSIS)\s*\n"
    parts = re.split(pattern, text)
    i = 1
    while i < len(parts) - 1:
        sections[parts[i].strip()] = parts[i + 1].strip()
        i += 2
    return sections

# ------------------------------------------------------------------------------
# Routes
# ------------------------------------------------------------------------------

@app.get("/health")
def health_check():
    return {"status": "healthy"}


@app.post("/api/analyze")
async def analyze_job(request: JobRequest):
    job_description = sanitize_input(request.job_description)

    if len(job_description) < 50:
        raise HTTPException(
            status_code=400,
            detail="Job description is too short. Please provide more detail."
        )

    try:
        client = get_openai_client()
        model = os.environ.get("OPENAI_MODEL", "gpt-4o")

        response = client.chat.completions.create(
            model=model,
            messages=[
                {
                    "role": "system",
                    "content": "You are an expert career coach helping job seekers craft strong applications."
                },
                {
                    "role": "user",
                    "content": build_prompt(job_description)
                }
            ],
            temperature=0.7,
            max_tokens=2000
        )

        result_text = response.choices[0].message.content
        sections = parse_sections(result_text)

        return {
            "cover_letter": sections.get("COVER LETTER", ""),
            "interview_questions": sections.get("INTERVIEW QUESTIONS", ""),
            "skills_gap_analysis": sections.get("SKILLS GAP ANALYSIS", ""),
        }

    except Exception as e:
        logger.error(f"Error calling OpenAI: {str(e)}")
        raise HTTPException(status_code=500, detail="An error occurred. Please try again.")


# ------------------------------------------------------------------------------
# Serve frontend
# ------------------------------------------------------------------------------

app.mount("/", StaticFiles(directory="static", html=True), name="static")
