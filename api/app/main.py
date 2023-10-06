import os
import sys
import boto3
import logging
import subprocess
from fastapi import FastAPI
from api.api_v1.api import router as api_router

logging.getLogger().setLevel(logging.INFO)
logger = logging.getLogger()

app = FastAPI()

@app.get("/")
async def root():
    return {"message": "API for question answering bot"}

app.include_router(api_router, prefix="/api/v1")
