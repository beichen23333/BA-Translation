set -euo pipefail

REGION=${1:-JP}
TYPE=${2:-Table}
THREADS=${3:-10}
SPECIFIC_PACKS=${4:-}

INFO_FILE="./info.json"

decrypt_zip_file() {
    local zip_file=$1
    echo "正在解密ZIP文件: $zip_file"
    
    if python3 decrypt_zip.py "$zip_file"; then
        echo "解密成功: $zip_file"
    else
        echo "错误: 解密失败: $zip_file"
        return 1
    fi
}

ADDRESSABLE_CATALOG_URL=$(jq -r ".[\"$REGION\"].AddressableCatalogUrl" "$INFO_FILE")
if [ "$ADDRESSABLE_CATALOG_URL" = "null" -o -z "$ADDRESSABLE_CATALOG_URL" ]; then
  echo "错误: info.json 中 $REGION.AddressableCatalogUrl 不存在"
  exit 1
fi

download_file() {
  local url=$1
  local output=$2
  local file_type=$3
  local max_retries=3
  local retry_count=0
  mkdir -p "$(dirname "$output")"

  while [ $retry_count -lt $max_retries ]; do
    echo "正在下载: $url (尝试 $((retry_count+1))/$max_retries)"
    http_status=$(curl -s -w "%{http_code}" -o "$output" "$url")
    if [ "$http_status" -eq 200 ] && [ -s "$output" ]; then
      echo "下载成功: $output"
      
      if [[ "$output" == *.zip ]] && [ "$file_type" = "Media" ]; then
        decrypt_zip_file "$output"
      elif [[ "$output" == *.zip ]]; then
        echo "跳过ZIP文件解密: $output"
      fi
      
      return 0
    else
      echo "下载失败 (HTTP $http_status): $url"
      rm -f "$output"
      retry_count=$((retry_count+1))
      sleep 2
    fi
  done
  echo "错误: 无法下载 $url"
  return 1
}

extract_media_filenames() {
  local json_file=$1
  if [ ! -f "$json_file" ]; then
    echo "错误: MediaCatalog文件不存在: $json_file"
    return 1
  fi
  
  jq -r '.MediaResources | to_entries[] | .value.path | gsub("\\\\"; "/")' "$json_file" 2>/dev/null || {
    echo "错误: 解析MediaCatalog文件失败: $json_file"
    return 1
  }
}

run_memorypack_repacker() {
  echo "运行 MemoryPackRepacker..."
  chmod +x ./MemoryPackRepacker
  
  if [ -f "./downloads/MediaResources/Catalog/MediaCatalog.bytes" ]; then
    ./MemoryPackRepacker deserialize media ./downloads/MediaResources/Catalog/MediaCatalog.bytes MediaCatalog.json
    echo "MediaCatalog.bytes 反序列化完成"
  else
    echo "警告: MediaCatalog.bytes 文件不存在，跳过反序列化"
  fi
  
  if [ -f "./downloads/TableBundles/TableCatalog.bytes" ]; then
    ./MemoryPackRepacker deserialize table ./downloads/TableBundles/TableCatalog.bytes TableCatalog.json
    echo "TableCatalog.bytes 反序列化完成"
  else
    echo "警告: TableCatalog.bytes 文件不存在，跳过反序列化"
  fi
  
  if [ -f "./downloads/Android_PatchPack/BundlePackingInfo.bytes" ]; then
    ./MemoryPackRepacker deserialize asset ./downloads/Android_PatchPack/BundlePackingInfo.bytes BundlePackingInfo-Android.json
    echo "BundlePackingInfo-Android.bytes 反序列化完成"
  else
    echo "警告: BundlePackingInfo-Android.bytes 文件不存在，跳过反序列化"
  fi
  
  if [ -f "./downloads/iOS_PatchPack/BundlePackingInfo.bytes" ]; then
    ./MemoryPackRepacker deserialize asset ./downloads/iOS_PatchPack/BundlePackingInfo.bytes BundlePackingInfo-iOS.json
    echo "BundlePackingInfo-iOS.bytes 反序列化完成"
  else
    echo "警告: BundlePackingInfo-iOS.bytes 文件不存在，跳过反序列化"
  fi
  
  echo "MemoryPackRepacker 运行完成！"
}

COMMON_DOWNLOADS=(
  "${ADDRESSABLE_CATALOG_URL}/TableBundles/TableCatalog.bytes|./downloads/TableBundles/TableCatalog.bytes|Common"
  "${ADDRESSABLE_CATALOG_URL}/MediaResources/Catalog/MediaCatalog.bytes|./downloads/MediaResources/Catalog/MediaCatalog.bytes|Common"
  "${ADDRESSABLE_CATALOG_URL}/Android_PatchPack/BundlePackingInfo.bytes|./downloads/Android_PatchPack/BundlePackingInfo.bytes|Common"
  "${ADDRESSABLE_CATALOG_URL}/iOS_PatchPack/BundlePackingInfo.bytes|./downloads/iOS_PatchPack/BundlePackingInfo.bytes|Common"
)

echo "下载Catalog"
for item in "${COMMON_DOWNLOADS[@]}"; do
  IFS='|' read -r url output file_type <<< "$item"
  download_file "$url" "$output" "$file_type"
done

run_memorypack_repacker

echo "=== 处理 $TYPE 类型文件 ==="
if [ "$TYPE" = "Table" ]; then
  TABLE_EXTRA_DOWNLOADS=(
    "${ADDRESSABLE_CATALOG_URL}/TableBundles/Excel.zip|./downloads/TableBundles/Excel.zip|Table"
    "${ADDRESSABLE_CATALOG_URL}/TableBundles/ExcelDB.db|./downloads/TableBundles/ExcelDB.db|Table"
  )
  
  for item in "${TABLE_EXTRA_DOWNLOADS[@]}"; do
    IFS='|' read -r url output file_type <<< "$item"
    download_file "$url" "$output" "$file_type"
  done

elif [ "$TYPE" = "Media" ]; then
  MEDIA_CATALOG_FILE="./MediaCatalog.json"
  
  echo "正在解析Media资源列表..."
  MEDIA_FILES=$(extract_media_filenames "$MEDIA_CATALOG_FILE")
  if [ $? -ne 0 ] || [ -z "$MEDIA_FILES" ]; then
    echo "错误: 无法提取Media资源列表"
    exit 1
  fi
  
  echo "使用 $THREADS 个线程下载Media资源..."
  export -f download_file
  export -f decrypt_zip_file
  
  # 创建临时目录用于存放Media文件
  MEDIA_TEMP_DIR="./media_temp"
  mkdir -p "$MEDIA_TEMP_DIR"
  
  echo "$MEDIA_FILES" | xargs -P "$THREADS" -I {} bash -c '
    path={}
    if [ -n "$path" ]; then
      download_url="'"$ADDRESSABLE_CATALOG_URL"'/MediaResources/${path}"
      output_file="'"$MEDIA_TEMP_DIR"'/MediaResources/${path}"
      download_file "$download_url" "$output_file" "Media"
    fi
  '
  
  # 将Media文件打包成ZIP
  echo "打包Media文件到ZIP..."
  cd "$MEDIA_TEMP_DIR"
  zip -r "../media_extracted_content.zip" .
  cd ..
  
  media_count=$(echo "$MEDIA_FILES" | wc -l)
  echo "已下载 $media_count 个Media资源文件，并打包到 media_extracted_content.zip"

elif [ "$TYPE" = "Bundle" ]; then
  if [ "$SPECIFIC_PACKS" = "catalog-only" ]; then
    echo "仅下载Catalog文件，跳过Bundle处理"
    exit 0
  fi
  
  BUNDLE_INFO_FILE="./BundlePackingInfo-Android.json"
  
  if [ ! -f "$BUNDLE_INFO_FILE" ]; then
    echo "错误: Bundle信息文件不存在: $BUNDLE_INFO_FILE"
    exit 1
  fi
  
  echo "正在解析Bundle资源列表..."
  
  if [ -n "$SPECIFIC_PACKS" ]; then
    echo "处理指定的Bundle包: $SPECIFIC_PACKS"
    PACK_NAMES=$(echo "$SPECIFIC_PACKS" | tr ',' '\n')
  else
    PACK_NAMES=$(jq -r '.FullPatchPacks[].PackName, .UpdatePacks[].PackName' "$BUNDLE_INFO_FILE" 2>/dev/null)
  fi
  
  if [ $? -ne 0 ] || [ -z "$PACK_NAMES" ]; then
    echo "错误: 无法解析Bundle信息文件"
    exit 1
  fi
  
  echo "使用 $THREADS 个线程处理Bundle包..."
  echo "$PACK_NAMES" | xargs -P "$THREADS" -I {} bash -c '
    pack_name={}
    if [ -n "$pack_name" ]; then
      download_url="'"$ADDRESSABLE_CATALOG_URL"'/Android_PatchPack/${pack_name}"
      output_file="./downloads/Android_PatchPack/${pack_name}"
      '"$(declare -f download_file)"'
      echo "下载Bundle包: $pack_name"
      if download_file "$download_url" "$output_file" "Bundle"; then
        echo "提取Bundle包: $pack_name"
        python3 extract_bundle.py "$output_file"
      fi
    fi
  '

  echo "打包Bundle提取内容到ZIP..."
  if [ -d "./bundle_output" ] && [ "$(ls -A ./bundle_output 2>/dev/null)" ]; then
    cd ./bundle_output
    zip -r "../bundle_extracted_content.zip" .
    cd ..
    echo "已创建bundle_extracted_content.zip"
  else
    echo "没有bundle提取内容可打包"
    touch bundle_empty.zip
  fi
  
  pack_count=$(echo "$PACK_NAMES" | wc -l)
  bundle_count=0
  
  while IFS= read -r pack_name; do
    if [ -n "$pack_name" ]; then
      pack_dir_name=$(basename "$pack_name" .zip)
      temp_count=$(find "./BA-Assets/Android_PatchPack/${pack_dir_name}" -type d -mindepth 1 -maxdepth 1 2>/dev/null | wc -l || echo 0)
      bundle_count=$((bundle_count + temp_count))
    fi
  done <<< "$PACK_NAMES"
  
  echo "已处理 $pack_count 个Bundle包，包含 $bundle_count 个bundle文件"

else
  echo "错误: 类型参数必须是 Table、Media 或 Bundle"
  exit 1
fi

echo "全部完成！"
