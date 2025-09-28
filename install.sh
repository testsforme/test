#!/usr/bin/env bash
set -euo pipefail

# Create target directory for the service
mkdir -p /opt/doc_converter

# Write the FastAPI application
cat > /opt/doc_converter/app.py <<'PY'
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import HTMLResponse
import subprocess
import docx
import tempfile
import os

app = FastAPI()

@app.post("/convert")
async def convert(file: UploadFile = File(...)):
    filename = file.filename.lower()
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name
    try:
        if filename.endswith(".docx"):
            doc = docx.Document(tmp_path)
            text = "\n".join([p.text for p in doc.paragraphs])
        elif filename.endswith(".doc"):
            result = subprocess.check_output(["antiword", tmp_path])
            text = result.decode("utf-8", errors="ignore")
        else:
            return {"error": "Unsupported format"}
        return {"text": text}
    finally:
        os.unlink(tmp_path)

@app.get("/form", response_class=HTMLResponse)
async def form():
    return """<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'><title>Upload Form</title></head>
<body>
<h1>Upload a Word document</h1>
<form action='/convert' method='post' enctype='multipart/form-data'>
    <input type='file' name='file' accept='.doc,.docx' required>
    <button type='submit'>Convert</button>
</form>
</body>
</html>"""
PY

# Determine the package manager and install required packages
install_packages() {
  packages="$@"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y $packages
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y $packages
  elif command -v yum >/dev/null 2>&1; then
    yum install -y $packages
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Syu --noconfirm $packages
  elif command -v zypper >/dev/null 2>&1; then
    zypper refresh
    zypper install -y $packages
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache $packages
  else
    echo "No supported package manager found" >&2
    return 1
  fi
}

# Install dependencies: Python, pip, antiword, libreoffice
install_packages python3 python3-pip antiword libreoffice || true

# Install pip packages
PYTHON=$(command -v python3 || command -v python)
$PYTHON -m ensurepip --upgrade || true
$PYTHON -m pip install --upgrade pip
$PYTHON -m pip install fastapi uvicorn python-docx

# Create a systemd service file for the converter
cat > /etc/systemd/system/doc_converter.service <<'SERVICE'
[Unit]
Description=Doc Converter API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/doc_converter
ExecStart=/usr/bin/python3 -m uvicorn app:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

# Reload systemd and start the service
systemctl daemon-reload
systemctl enable --now doc_converter.service
