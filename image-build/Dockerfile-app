FROM public.ecr.aws/docker/library/python:3.11.4-slim AS installer-image
WORKDIR /app
RUN DEBIAN_FRONTEND=noninteractive apt-get -qq update -y 2>/dev/null >/dev/null && \
    DEBIAN_FRONTEND=noninteractive apt-get -qq install -y \
    build-essential \
    curl \
    software-properties-common 2>/dev/null >/dev/null \
    && rm -rf /var/lib/apt/lists/*
ADD app/* ./
RUN pip install --user --upgrade -q -q pip && pip install --user -q -q -r requirements.txt


FROM public.ecr.aws/docker/library/python:3.11.4-slim
RUN DEBIAN_FRONTEND=noninteractive apt-get -qq update -y 2>/dev/null >/dev/null && \
    DEBIAN_FRONTEND=noninteractive apt-get -qq upgrade -y 2>/dev/null >/dev/null && \
    DEBIAN_FRONTEND=noninteractive apt install -qq -y curl 2>/dev/null >/dev/null && \
    addgroup --gid 8000 streamlit && \
    adduser --uid 8000 --gid 8000 --disabled-password --gecos "" streamlit
USER streamlit
WORKDIR /home/streamlit/app
COPY --chown=streamlit:streamlit --from=installer-image /root/.local /home/streamlit/.local/
COPY --chown=streamlit:streamlit app/*.py /home/streamlit/app/
ENV PATH=/home/streamlit/.local/bin:$PATH
EXPOSE 8501
HEALTHCHECK CMD curl --fail http://localhost:8501/_stcore/health
ENTRYPOINT ["streamlit", "run", "webapp.py", "--server.port=8501", "--server.address=0.0.0.0"]