import os
import boto3
from enum import Enum
from pydantic import BaseModel
from typing import List

class Text2TextModelName(str, Enum):
    modelId = os.environ.get('TEXT2TEXT_MODEL_ID')

class EmbeddingsModelName(str, Enum):
    modelId = os.environ.get('EMBEDDING_MODEL_ID')

class VectorDBType(str, Enum):
    FAISS = "faiss"

class Request(BaseModel):
    q: str
    user_session_id: str
    max_length: int = 500
    num_return_sequences: int = 1
    do_sample: bool = False
    verbose: bool = False
    max_matching_docs: int = 3  
    # Bedrock / Titan
    temperature: float = 0.1
    maxTokenCount: int = 512
    stopSequences: List = ['\n\nHuman:']
    topP: float = 0.9
    topK: int = 250
    
    text_generation_model: Text2TextModelName = Text2TextModelName.modelId
    embeddings_generation_model: EmbeddingsModelName = EmbeddingsModelName.modelId
    vectordb_s3_path: str = f"s3://{os.environ.get('CONTEXTUAL_DATA_BUCKET')}/faiss_index/"
    vectordb_type: VectorDBType = VectorDBType.FAISS

MODEL_ENDPOINT_MAPPING = {
    Text2TextModelName.modelId: os.environ.get('TEXT2TEXT_MODEL_ID'),
    EmbeddingsModelName.modelId: os.environ.get('EMBEDDING_MODEL_ID'),
}
