import os
import boto3
import logging
from urllib.parse import urlparse
from langchain.vectorstores import FAISS
from langchain.embeddings import BedrockEmbeddings

logger = logging.getLogger(__name__)

def load_vector_db_faiss(vectordb_s3_path: str, vectordb_local_path: str, embeddings_model: str, bedrock_service: str) -> FAISS:
    os.makedirs(vectordb_local_path, exist_ok=True)
    # download the vectordb files from S3
    # note that the following code is only applicable to FAISS
    # would need to be enhanced to support other vector dbs
    vectordb_files = ["index.pkl", "index.faiss"]
    for vdb_file in vectordb_files:        
        s3 = boto3.client('s3')
        fpath = os.path.join(vectordb_local_path, vdb_file)
        with open(fpath, 'wb') as f:
            parsed = urlparse(vectordb_s3_path)
            bucket = parsed.netloc
            path =  os.path.join(parsed.path[1:], vdb_file)
            logger.info(f"going to download from bucket={bucket}, path={path}, to {fpath}")
            s3.download_fileobj(bucket, path, f)
            logger.info(f"after downloading from bucket={bucket}, path={path}, to {fpath}")

    logger.info("Creating an embeddings object to hydrate the vector db")

    boto3_bedrock = boto3.client(service_name=bedrock_service)
    br_embeddings = BedrockEmbeddings(client=boto3_bedrock, model_id=embeddings_model)

    vector_db = FAISS.load_local(vectordb_local_path, br_embeddings)
    logger.info(f"vector db hydrated, type={type(vector_db)} it has {vector_db.index.ntotal} embeddings")

    return vector_db
