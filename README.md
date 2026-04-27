commands:
"--model", "majentik/gemma-4-E2B-it-TurboQuant-AWQ-4bit", "--host", "0.0.0.0", "--port", "8000", "--max-model-len", "10000", "--gpu-memory-utilization", "0.9", "--quantization", "awq", "--reasoning-parser", "gemma4", "--tool-call-parser", "gemma4", "--enable-auto-tool-choice", "--limit-mm-per-prompt","image=4,audio=1", "--async-scheduling", "--mm-processor-kwargs", '{"max_soft_tokens": 1120}', "--chat-template", "examples tool_chat_template_gemma4.jinja", "--max-num-seqs", "2",

restart: unless-stopped
