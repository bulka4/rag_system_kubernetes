from fastapi import FastAPI
from ray import serve
from semantic_search_agent.agent import RAGAgent
from transformers import pipeline
import os

app = FastAPI()
# mcp_server_url - URL of the MCP server with a tool for semantic search used by the Agent (RAGAgent class) of the format http://<server-ip-or-dns>:8000/mcp/
# answer_model - Model used by the 'Answer' agent (from the RAGAgent class) for generating the final answer.
mcp_server_url = os.getenv('MCP_SERVER_URL') or "http://localhost:8000/mcp/"
answer_model = pipeline("text2text-generation", model="google/flan-t5-base")


@serve.deployment(ray_actor_options={"num_cpus": 2})
@serve.ingress(app)
class RAGAgentService:
    def __init__(self):
        self.rag_agent = RAGAgent(
            mcp_server_url=mcp_server_url
            ,answer_model=answer_model
        )


    @app.get("/ask")
    async def ask(self, query: str) -> dict:
        """
        Function for answering a question using the Agent (LangGraph graph). Output is a dictionary with the following keys:
        - retrieved_docs: Retrieved documents relevant to the question, used for generating the answer.
        - answer: The generated answer. 
        """

        final_state = self.rag_agent.answer(query)
        return final_state