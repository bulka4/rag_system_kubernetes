from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from ray import serve
from rag_workflow import RAGWorkflow
from transformers import pipeline
import os
import traceback

# URL of the MCP server with a tool for semantic search used in the RAG workflow (RAGWorkflow class) of the format http://<server-ip-or-dns>:8000/mcp/
mcp_server_url = os.getenv('MCP_SERVER_URL') or "http://localhost:8000/mcp/"

app = FastAPI()

# Exception handler to see the exact error in Python code when we make a Rest API call and it doesn't work.
@app.exception_handler(Exception)
async def debug_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={"error": str(exc), "trace": traceback.format_exc()},
    )


@serve.deployment(ray_actor_options={"num_cpus": 2})
@serve.ingress(app)
class RAGService:
    def __init__(
        self
        ,mcp_server_url
    ):
        self.mcp_server_url = mcp_server_url
        self.answer_model = None
        self.rag_workflow = None


    def init_rag(
        self
    ):
        if self.rag_workflow == None:
            self.rag_workflow = RAGWorkflow(
                mcp_server_url=self.mcp_server_url
                # Model used by the 'Answer' agent for generating the final answer.
                ,answer_model=pipeline("text2text-generation", model="google/flan-t5-base")
            )


    @app.get("/ask")
    async def ask(self, query: str) -> dict:
        """
        Function for answering a question using the RAG LangGraph workflow. Output is a dictionary with the following keys:
        - retrieved_docs: Retrieved documents relevant to the question, used for generating the answer.
        - answer: The generated answer. 
        """

        self.init_rag()
        final_state = await self.rag_workflow.answer(query)
        return final_state

rag_service = RAGService.bind(
    mcp_server_url=mcp_server_url
)