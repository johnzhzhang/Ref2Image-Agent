# Ref2Image Agent (参考图生图 Agent)

上传参考图，自动提取特征、生成图片、评估一致性并迭代优化，确保生成结果严格匹配参考图和提示词要求。

## Features

- **参考图驱动**：上传任意角色/风格参考图，agent 自动提取详细视觉特征
- **智能提示词优化**：Flash 3.5 基于参考图特征生成结构化提示词
- **严格质量评估**：逐张评分（满分10，>=8通过），覆盖角色一致性、人体解剖、服装物理、提示词符合度
- **自动迭代优化**：不通过则修正提示词重新生成，最多5轮，5轮后选最高分交付
- **单张编辑**：对最终图片进行针对性修改
- **Memory Bank**：跨会话记忆用户偏好

## Architecture

```
用户上传参考图 → add_reference_image (Flash 提取视觉特征)
        ↓
用户描述场景 → optimize_prompt (Flash 生成结构化提示词)
        ↓
generate_images (gemini-3.1-flash-image 生成候选图, 数量=目标+1)
        ↓
evaluate_and_select (Flash 对照参考图+提示词逐张评分)
        ↓
  >=8分 → 通过 ✅
  <8分  → refine_prompt → generate_images → evaluate (最多5轮)
        ↓
5轮后仍无合格 → 选最高分交付
        ↓
edit_image → 用户反馈修改单张图
```

## Quick Start

```bash
# 安装依赖
pip install -e .

# 设置环境变量
export GOOGLE_GENAI_USE_VERTEXAI=1
export GOOGLE_CLOUD_PROJECT=your-project-id
export GOOGLE_CLOUD_LOCATION=global

# ADK Web UI 本地运行
adk web --port 8080

# 一键部署到 Agent Engine
./deploy.sh your-project-id us-central1
```

## 使用方式

1. 上传参考图（角色/风格/场景均可），agent 会自动提取特征并确认风格
2. 描述想要的场景，指定生成数量（默认1张）
3. Agent 自动生成 → 评估 → 迭代优化
4. 对结果不满意可说"修改第X张图，xxx"进行编辑

## 评估维度

| 维度 | 检查内容 | 扣分 |
|------|----------|------|
| 角色一致性 | 颜色、配饰、比例、标识 | 1-3分 |
| 人体解剖 | 手指数量、面部、身体结构、对称性 | 2-3分 |
| 服装/道具 | 物理合理性、握持姿势、层次关系 | 1-2分 |
| 提示词符合度 | 场景、动作、服装是否匹配要求 | 1-2分 |
| 构图质量 | 美学、清晰度 | 1分 |

## 配置

| 参数 | 值 | 说明 |
|------|------|------|
| Orchestrator | gemini-3.5-flash | 意图理解 + 工具调度 |
| 提示词优化 | gemini-3.5-flash (temp=0.7) | 生成结构化提示词 |
| 图片生成 | gemini-3.1-flash-image (temp=0.3) | 生成图片 |
| 评估 | gemini-3.5-flash (temp=0.2) | 严格评分 |
| 通过阈值 | >=8/10 | 严格标准 |
| 最大重试 | 5轮 | 5轮后选最高分 |

## 文件结构

```
├── README.md
├── agent.py          # root_agent + 所有 tools
├── pyproject.toml    # Python 依赖
└── deploy.sh         # 一键部署脚本
```
