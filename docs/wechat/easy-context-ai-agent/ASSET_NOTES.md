# 素材说明

## 应用截图

- `assets/01-product-settings.png`：来源为工程现有 `docs/screenshots/settings.png`，原样复制，用于展示 Easy Context 设置界面。
- `assets/02-product-finder-menu.png`：来源为工程现有 `docs/screenshots/usage.png`，原样复制，用于展示 Finder 右键菜单使用场景。

## Mermaid 配图

- `assets/03-human-ai-boundary.mmd`：人和 AI Agent 的责任边界。使用横向三栏布局：左侧是人的方向、取舍、验收与最终责任，中间是共同决策与协作，右侧是 AI 的探索、实现、测试与证据；双向箭头表达目标和任务合同如何交给 AI，以及方案、代码、风险证据和验收依据如何返回。图中明确“共同形成判断，人最终拍板并承担责任”。
- `assets/03-agent-collaboration.mmd`：Agent 协作链路。表达人的目标、边界与验收如何驱动主 Agent、规划/探索、实现/测试、独立审查、真机验收和规则沉淀。
- `assets/04-runtime-architecture.mmd`：运行时架构。准确表达 Finder 右键、沙盒 Finder 扩展、轻量动作、`easycontext://` + IPC token、非沙盒宿主、Core 与共享配置的关系。
- `assets/05-feedback-loop.mmd`：反馈闭环。表达目标、显式假设、实现、自动测试、真机验证，以及失败后的根因分析和知识沉淀。

责任边界图采用 `flowchart TB` 外层与内部 `direction LR` 横向责任卡，方便读者观察全局；其余三张图使用纵向 `flowchart TB`，面向公众号手机阅读。全部使用浅冷灰背景、圆角卡片和蓝/紫/橙/绿/珊瑚红语义色，字体优先 PingFang SC、Hiragino Sans GB、Arial Unicode MS。

## 导出产物

四张 Mermaid 图已同时保留源文件、SVG 与 PNG。文章引用 PNG，SVG 用于后续编辑和高清导出。

本次使用 Mermaid CLI `11.12.0` 和本机 Chrome 渲染，命令模板如下：

```bash
npx --yes @mermaid-js/mermaid-cli@11.12.0 \
  -i assets/03-agent-collaboration.mmd \
  -o assets/03-agent-collaboration.png \
  -b '#F3F6FA' -w 1200 -s 2
```

其余图替换输入输出文件名即可；SVG 导出移除 `-s 2` 并把后缀改为 `.svg`。

## 头图（ImageGen）

`assets/00-cover-ai-agent.png` 最终采用 B 版小牛封面，使用内置 ImageGen 的定向编辑模式制作。以原有科技工作台封面为编辑目标，只重做中央角色，保留五个 Agent 能力节点、连线、决策动作、镜头和整体构图。

最终提示要点：宽幅科技出版插画；原创拟人小牛在中央透明工作台调度五类 Agent 能力；使用暖赭橙色低多边形切面、块状长口鼻、小而略显困倦的眼睛和克制木讷的表情，在抽象感与整洁的出版视觉之间取得平衡；只穿统一的深蓝无袖马甲，两只前臂使用一致的牛体结构和深色分趾牛蹄，不出现人类手指、袖口或混合肢体；保留浅冷灰与淡蓝背景、蓝紫 Agent 节点、橙色决策节点和绿色验证节点；无文字、字母、数字、Logo、水印或伪 UI 文案。

封面在两版候选中最终采用 B 版，并通过第二次局部编辑统一左右分趾牛蹄。候选过程文件已从发布素材包中移除，仅保留文章实际使用的 `assets/00-cover-ai-agent.png`。
