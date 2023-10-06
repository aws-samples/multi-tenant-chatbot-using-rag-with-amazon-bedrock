import os
import boto3
import botocore

from langchain.document_loaders import CSVLoader
from langchain.text_splitter import CharacterTextSplitter
from langchain.indexes.vectorstore import VectorStoreIndexWrapper
from langchain.embeddings import BedrockEmbeddings
from langchain.llms.bedrock import Bedrock
from langchain.vectorstores import FAISS

LOCAL_RAG_DIR="data"
FAISS_INDEX_DIR = "faiss_index"
if not os.path.exists(LOCAL_RAG_DIR):
   os.makedirs(LOCAL_RAG_DIR)

embeddings_model = os.environ.get('EMBEDDING_MODEL_ID')
bedrock_service = os.environ.get('BEDROCK_SERVICE')
boto3_bedrock = boto3.client(service_name=bedrock_service)
br_embeddings = BedrockEmbeddings(client=boto3_bedrock, model_id=embeddings_model)

TENANTS=["tenanta", "tenantb"]

for t in TENANTS:
    if t == "tenanta":
        DATAFILE="Amazon_SageMaker_FAQs.csv"
    elif t == "tenantb":
        DATAFILE="Amazon_EMR_FAQs.csv"

    loader = CSVLoader(f"./{LOCAL_RAG_DIR}/{DATAFILE}")
    documents_aws = loader.load()
    print(f"documents:loaded:size={len(documents_aws)}")
    
    docs = CharacterTextSplitter(chunk_size=2000, chunk_overlap=400, separator=",").split_documents(documents_aws)
    
    print(f"Documents:after split and chunking size={len(docs)}")
    
    vector_db = FAISS.from_documents(
        documents=docs,
        embedding=br_embeddings, 
    )

    print(f"vector_db:created={vector_db}::")

    vector_db.save_local(f"{FAISS_INDEX_DIR}-{t}")
    
    S3_BUCKET=f"contextual-data-{t}-{os.environ.get('RANDOM_STRING')}"
    print(f"S3 Bucket: ${S3_BUCKET}")

    s3_path = f"s3://{S3_BUCKET}/{DATAFILE}"
    
    s3 = boto3.resource('s3')

    try:
        to_upload = os.listdir(f"./{FAISS_INDEX_DIR}-{t}")
        for file in to_upload:
            s3.Bucket(S3_BUCKET).upload_file(f"./{FAISS_INDEX_DIR}-{t}/{file}", f"{FAISS_INDEX_DIR}/{file}", )
    except botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == "404":
            print("The object does not exist.")
        else:
            raise
