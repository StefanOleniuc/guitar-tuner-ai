FROM python:3.11-slim

WORKDIR /app

# Instalăm setuptools<81 ÎNAINTE de orice altceva (necesar pentru CREPE/hmmlearn).
# --no-build-isolation la pasul următor face ca pip să folosească
# acest setuptools în loc să creeze un mediu izolat cu versiune mai nouă.
RUN pip install --no-cache-dir "setuptools<81" wheel

COPY requirements.txt .
RUN pip install --no-cache-dir --no-build-isolation -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
