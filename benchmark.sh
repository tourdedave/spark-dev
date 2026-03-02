#!/bin/bash

URL="http://192.168.1.226:8000/v1/chat/completions"
#MODEL="nvidia/Llama-3.3-70B-Instruct-NVFP4"
MODEL="nvidia/Qwen3-30B-A3B-NVFP4"
PROMPT="tell me something I don't know. limit your answer to at most 4 sentences."
CONCURRENCY=${1:-4}

echo "Running with $CONCURRENCY concurrent requests..."

start=$(($(date +%s%N)/1000000))

# Temporary file to store token counts
TMPFILE=$(mktemp)

for i in $(seq 1 $CONCURRENCY); do
  (
    response=$(curl -s -X POST $URL \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"$MODEL\",
        \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}]
      }")

    # Extract the text (bash-safe)
    text=$(echo "$response" | jq -r '.choices[0].message.content')

    # Count tokens (approx: whitespace split)
    tok_count=$(echo "$text" | wc -w | tr -d ' ')

    echo $tok_count >> $TMPFILE
  ) &
done

wait

end=$(($(date +%s%N)/1000000))

elapsed_ms=$((end - start))
elapsed_sec=$(echo "scale=3; $elapsed_ms / 1000" | bc)

total_tokens=$(awk '{s+=$1} END {print s}' $TMPFILE)
rm $TMPFILE

echo
echo "=== Results ==="
echo "Elapsed time: ${elapsed_sec}s"
echo "Total tokens: ${total_tokens}"
echo "Tokens/sec: $(echo "scale=2; $total_tokens / $elapsed_sec" | bc)"
echo