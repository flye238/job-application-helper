import azure.functions as func
import logging
import json
import os
import re
from openai import OpenAI
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

def get_openai_client() -> OpenAI:
    key_vault_uri = os.environ["KEY_VAULT_URI"]
    credential = ManagedIdentityCredential()
    secret_client = SecretClient(vault_url=key_vault_uri, credential=credential)
    api_key = secret_client.get_secret("openai-api-key").value
    return OpenAI(api_key=api_key)

def sanitize_input(text: str, max_length: int = 5000) -> str:
    if not isinstance(text, str):
        raise ValueError("Input must be a string.")
    text = text.strip()
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)
    if len(text) > max_length:
        text = text[:max_length]
    return text

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
Keep it to 3-4 paragraphs. Do not include placeholder text like [Your Name] —
write it as a polished template the user can personalize.

## INTERVIEW QUESTIONS
List 8 likely interview questions the hiring manager might ask based on this
job description. For each question, provide a brief 1-2 sentence tip on how
to approach the answer.

## SKILLS GAP ANALYSIS
Identify the top 5 skills or qualifications emphasized in the job description.
For each, rate how commonly candidates lack this skill (High / Medium / Low gap)
and provide one actionable suggestion for how to develop or demonstrate it.
"""

def parse_sections(text: str) -> dict:
    sections = {}
    pattern = r"##\s+(COVER LETTER|INTERVIEW QUESTIONS|SKILLS GAP ANALYSIS)\s*\n"
    parts = re.split(pattern, text)
    i = 1
    while i < len(parts) - 1:
        sections[parts[i].strip()] = parts[i + 1].strip()
        i += 2
    return sections

@app.route(route="analyze", methods=["POST"])
def analyze_job(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("analyze_job function triggered.")

    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "Invalid JSON in request body."}),
            status_code=400, mimetype="application/json"
        )

    job_description = body.get("job_description", "")

    if not job_description:
        return func.HttpResponse(
            json.dumps({"error": "job_description field is required."}),
            status_code=400, mimetype="application/json"
        )

    try:
        job_description = sanitize_input(job_description)
    except ValueError as e:
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=400, mimetype="application/json"
        )

    if len(job_description) < 50:
        return func.HttpResponse(
            json.dumps({"error": "Job description is too short. Please provide more detail."}),
            status_code=400, mimetype="application/json"
        )

    try:
        client = get_openai_client()
        model = os.environ.get("OPENAI_MODEL", "gpt-4o")

        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You are an expert career coach helping job seekers craft strong applications."},
                {"role": "user", "content": build_prompt(job_description)}
            ],
            temperature=0.7,
            max_tokens=2000
        )

        result_text = response.choices[0].message.content
        sections = parse_sections(result_text)

        return func.HttpResponse(
            json.dumps({
                "cover_letter": sections.get("COVER LETTER", ""),
                "interview_questions": sections.get("INTERVIEW QUESTIONS", ""),
                "skills_gap_analysis": sections.get("SKILLS GAP ANALYSIS", ""),
                "raw": result_text
            }),
            status_code=200, mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Error: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": "An error occurred. Please try again."}),
            status_code=500, mimetype="application/json"
        )
