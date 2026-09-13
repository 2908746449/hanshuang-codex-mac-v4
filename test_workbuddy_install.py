#!/usr/bin/env python3
"""测试 WorkBuddy 安装功能"""

import sys
import os

# 添加项目路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# 模拟打包环境
class MockMEIPASS:
    pass

# 设置模拟的打包环境变量
sys._MEIPASS = "dist/寒霜破甲工具.app/Contents/Frameworks"
sys.executable = "dist/寒霜破甲工具.app/Contents/MacOS/寒霜破甲工具"

# 导入主模块
from fj_tool import _res

# 测试资源路径
print("=== 测试资源路径解析 ===")
print(f"sys._MEIPASS: {sys._MEIPASS}")
print(f"sys.executable: {sys.executable}")
print()

# 测试查找 install-workbuddy.sh
script_path = _res('install-workbuddy.sh')
print(f"install-workbuddy.sh 路径: {script_path}")
print(f"文件存在: {os.path.exists(script_path)}")
print()

# 测试查找寒霜提示词文件
for prompt_file in ['寒霜v4.md', '寒霜v3.md', '寒霜v1.2.md']:
    path = _res(prompt_file)
    print(f"{prompt_file}: {path}")
    print(f"  存在: {os.path.exists(path)}")

print()
print("=== 测试完成 ===")
