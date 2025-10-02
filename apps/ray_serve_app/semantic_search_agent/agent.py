"""
In this script we create a LangGraph workflow for answering a question based on relevant documents found in a vector db.

It uses two agents:
- The 'Retriever' one which is performing a semantic search (using a MCP tool)
- The 'Answer' one which is generating a final answer based on the documents found by the Retriever.
"""

from langgraph.graph import StateGraph, END
from typing import Dict, Any
from transformers import pipeline, Pipeline
import asyncio

from fastmcp.client.transports import StreamableHttpTransport
from fastmcp import Client


class RAGAgent:
    def __init__(
        self
        ,mcp_server_url: str = "http://localhost:8000/mcp/"
        ,answer_model: Pipeline = None
    ):
        """
        Parameters:
        - mcp_server_url: URL of the MCP server with tools used by the agent
        - answer_model: Model used by the 'Answer' agent for generating the final answer. It is created using the transformers.pipeline() function.
        """
        self.mcp_server_url = mcp_server_url
        self.answer_model = answer_model or pipeline("text2text-generation", model="google/flan-t5-base")


        # ------------------------
        # Create the LangGraph graph
        # ------------------------
        workflow = StateGraph(dict)

        workflow.add_node("retriever", self.retriever_agent)
        workflow.add_node("answer", self.answer_agent)

        workflow.set_entry_point("retriever")
        workflow.add_edge("retriever", "answer")
        workflow.add_edge("answer", END)

        self.graph = workflow.compile()



    # ------------------------
    # Helper: Call MCP Tool
    # ------------------------
    async def mcp_search_docs(self, query: str) -> list[str]:
        """
        Use the MCP server's search_docs tool to retrieve documents. Before we run this function we need to start the
        mcp_server/mcp_server.py server from this repo.
        """

        # Connect to the MCP server using HTTP Transport
        transport = StreamableHttpTransport(url=self.mcp_server_url)
        client = Client(transport)

        async with client:
            result = await client.call_tool("search_docs", {"query": query})

        return result


    # ------------------------
    # Agent 1: Retriever
    # ------------------------
    async def retriever_agent(self, state: Dict[str, Any]) -> Dict[str, Any]:
        query = state["query"]
        # Perform semantic search - find relevant documents in a vector db, similar to the query
        result = await self.mcp_search_docs(query)
        retrieved_docs = result.data

        return {"query": query, "retrieved_docs": retrieved_docs}


    # ------------------------
    # Agent 2: Answer Generator
    # ------------------------
    async def answer_agent(self, state: Dict[str, Any]) -> Dict[str, Any]:
        query = state["query"]
        # Take retrieved relevant documents found by the Retriever agent
        retrieved_docs = state["retrieved_docs"]

        context = "\n".join(retrieved_docs)
        prompt = f"Answer the question based on the following documents:\n{context}\n\nQuestion: {query}"

        # Get the current event loop
        loop = asyncio.get_event_loop()

        # Generate an answer based on the retrieved documents. Run it as an async function so other async functions
        # can run at the same time.
        answer = await loop.run_in_executor(
            None
            ,lambda: self.answer_model(prompt, max_new_tokens=100, do_sample=False)[0]["generated_text"]
        )
        return {"answer": answer, "retrieved_docs": retrieved_docs}


    async def answer(self, query: str) -> dict:
        """
        Function for answering a question using the LangGraph graph. Output is a dictionary with the following keys:
        - retrieved_docs: Retrieved documents relevant to the question, used for generating the answer.
        - answer: The generated answer. 
        """

        final_state = await self.graph.ainvoke({"query": query})
        return final_state


# ------------------------
# Run an example
# ------------------------
if __name__ == "__main__":
    rag_agent = RAGAgent()
    query = "What is MLflow?"
    final_state = asyncio.run(rag_agent.answer(query))
    print("Retrieved Docs:", final_state["retrieved_docs"])
    print("Final Answer:", final_state["answer"])
