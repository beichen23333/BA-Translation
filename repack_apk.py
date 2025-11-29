# repack_apk.py
import os
import zipfile
import shutil
from pathlib import Path

def create_apk_from_extracted(extracted_dir, output_apk):
    """
    将提取的APK内容重新打包为APK文件
    """
    print(f"开始打包APK: {output_apk}")
    
    # 确保输出目录存在
    os.makedirs(os.path.dirname(output_apk), exist_ok=True)
    
    # 创建新的APK文件
    with zipfile.ZipFile(output_apk, 'w', zipfile.ZIP_DEFLATED) as apk_zip:
        # 遍历提取的目录结构
        for root, dirs, files in os.walk(extracted_dir):
            for file in files:
                file_path = os.path.join(root, file)
                
                # 计算在APK中的相对路径
                arcname = os.path.relpath(file_path, extracted_dir)
                
                # 添加到APK
                apk_zip.write(file_path, arcname)
                print(f"添加文件: {arcname}")
    
    print(f"APK打包完成: {output_apk}")
    return output_apk

def find_main_apk_files(temp_dir):
    """
    在提取的目录中查找主要的APK文件组件
    """
    data_dir = os.path.join(temp_dir, "Data")
    
    if not os.path.exists(data_dir):
        print(f"错误: 数据目录不存在: {data_dir}")
        return None
    
    # 查找可能的APK组件
    apk_components = []
    for item in os.listdir(data_dir):
        item_path = os.path.join(data_dir, item)
        if os.path.isfile(item_path) and item.endswith('.apk'):
            apk_components.append(item_path)
        elif os.path.isdir(item_path):
            # 检查是否是APK解压后的目录
            if os.path.exists(os.path.join(item_path, "AndroidManifest.xml")):
                apk_components.append(item_path)
    
    return apk_components

def merge_apk_components(components, output_apk):
    """
    合并多个APK组件为一个APK
    """
    if not components:
        print("错误: 没有找到APK组件")
        return None
    
    # 如果是单个APK文件，直接使用
    if len(components) == 1 and components[0].endswith('.apk'):
        shutil.copy2(components[0], output_apk)
        print(f"使用现有APK: {output_apk}")
        return output_apk
    
    # 如果是解压的目录，重新打包
    for component in components:
        if os.path.isdir(component):
            return create_apk_from_extracted(component, output_apk)
    
    return None

def main():
    TEMP_DIR = "Temp"
    OUTPUT_APK = "bluearchive_repacked.apk"
    
    # 检查是否已经提取了文件
    if not os.path.exists(os.path.join(TEMP_DIR, "Data")):
        print("错误: 请先运行 setup_apk.py 提取XAPK文件")
        return
    
    # 查找APK组件
    components = find_main_apk_files(TEMP_DIR)
    
    if not components:
        print("错误: 未找到APK文件组件")
        return
    
    print(f"找到APK组件: {components}")
    
    # 重新打包APK
    result_apk = merge_apk_components(components, OUTPUT_APK)
    
    if result_apk and os.path.exists(result_apk):
        print(f"✅ APK重新打包成功: {result_apk}")
        print(f"文件大小: {os.path.getsize(result_apk)} 字节")
    else:
        print("❌ APK重新打包失败")

if __name__ == "__main__":
    main()
