set -euo pipefail

smart_commit() {
  local file_type=$1
  local pattern=$2
  local commit_msg=$3
  local batch_size=200
  local batch_num=1
  
  echo "Processing $file_type files..."
  
  if ! find . -name "$pattern" -type f | grep -q .; then
    echo "No $file_type files found, skipping..."
    return 0
  fi
  
  local file_count=0
  local current_batch=()
  
  while IFS= read -r -d '' file; do
    if [ -f "$file" ]; then
      current_batch+=("$file")
      ((file_count++))
      
      if [ ${#current_batch[@]} -ge $batch_size ]; then
        echo "Adding ${#current_batch[@]} $file_type files (batch $batch_num)"
        
        for file_path in "${current_batch[@]}"; do
          git add -- "$file_path"
        done
        
        if ! git diff --staged --quiet; then
          if git commit -m "$commit_msg (batch $batch_num)"; then
            echo "✓ Committed batch $batch_num"
            if git push origin; then
              echo "✓ Pushed batch $batch_num"
            else
              echo "✗ Failed to push batch $batch_num, resetting..."
              git reset --hard HEAD~1
              for file_path in "${current_batch[@]}"; do
                git add -- "$file_path"
              done
            fi
          else
            echo "✗ Failed to commit batch $batch_num"
            git reset
          fi
        else
          echo "No changes to commit in batch $batch_num"
          current_batch=()
        fi
        
        batch_num=$((batch_num + 1))
        current_batch=()
      fi
    fi
  done < <(find . -name "$pattern" -type f -print0 2>/dev/null)
  
  if [ ${#current_batch[@]} -gt 0 ]; then
    echo "Adding final batch of ${#current_batch[@]} $file_type files"
    
    for file_path in "${current_batch[@]}"; do
      git add -- "$file_path"
    done
    
    if ! git diff --staged --quiet; then
      if git commit -m "$commit_msg (final batch)"; then
        echo "✓ Committed final batch"
        if git push origin; then
          echo "✓ Pushed final batch"
        else
          echo "✗ Failed to push final batch"
          git reset --hard HEAD~1
        fi
      else
        echo "✗ Failed to commit final batch"
        git reset
      fi
    else
      echo "No changes to commit in final batch"
    fi
  fi
  
  echo "Completed processing $file_count $file_type files"
}

echo "Starting smart commit process..."

if git diff --cached --quiet && git diff --quiet; then
  echo "No changes detected in BA-Assets, skipping commit process"
  cd ..
  exit 0
fi

BA_VERSION_NAME="${BA_VERSION_NAME:-}"
if [ -z "$BA_VERSION_NAME" ]; then
  echo "错误: BA_VERSION_NAME 环境变量未设置"
  exit 1
fi

echo "使用版本号: $BA_VERSION_NAME"

smart_commit "json" "*.json" "Update Assets: json files - version $BA_VERSION_NAME"
smart_commit "zip" "*.zip" "Update Assets: zip files - version $BA_VERSION_NAME"
smart_commit "png" "*.png" "Update Assets: png files - version $BA_VERSION_NAME"
smart_commit "jpg" "*.jpg" "Update Assets: jpg files - version $BA_VERSION_NAME"
smart_commit "ogg" "*.ogg" "Update Assets: ogg files - version $BA_VERSION_NAME"
smart_commit "mp4" "*.mp4" "Update Assets: mp4 files - version $BA_VERSION_NAME"

echo "Processing other file types..."
other_files=()
while IFS= read -r -d '' file; do
  other_files+=("$file")
done < <(find . -type f ! -name "*.json" ! -name "*.zip" ! -name "*.png" ! -name "*.jpg" ! -name "*.ogg" ! -name "*.mp4" -print0 2>/dev/null)

if [ ${#other_files[@]} -gt 0 ]; then
  echo "Found ${#other_files[@]} other files"
  
  batch_num=1
  current_batch=()
  
  for file_path in "${other_files[@]}"; do
    current_batch+=("$file_path")
    
    if [ ${#current_batch[@]} -ge 200 ]; then
      for f in "${current_batch[@]}"; do
        git add -- "$f"
      done
      
      if ! git diff --staged --quiet; then
        if git commit -m "Update Assets: other files batch $batch_num - version $BA_VERSION_NAME"; then
          if git push origin; then
            echo "✓ Pushed other files batch $batch_num"
          else
            echo "✗ Failed to push other files batch $batch_num"
            git reset --hard HEAD~1
          fi
        fi
      else
        echo "No changes to commit in other files batch $batch_num"
      fi
      
      batch_num=$((batch_num + 1))
      current_batch=()
    fi
  done
  
  if [ ${#current_batch[@]} -gt 0 ]; then
    for f in "${current_batch[@]}"; do
      git add -- "$f"
    done
    
    if ! git diff --staged --quiet; then
      git commit -m "Update Assets: final other files - version $BA_VERSION_NAME"
      git push origin
    else
      echo "No changes to commit in final other files batch"
    fi
  fi
else
  echo "No other files found"
fi

echo "Smart commit process completed"
