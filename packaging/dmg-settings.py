# dmgbuild 配置：直接写 .DS_Store，不依赖 Finder 自动化。
# 用法：dmgbuild -s packaging/dmg-settings.py -D app=<.app路径> -D notes=<说明文件> \
#               -D volicon=<.icns> "Easy Context" dist/EasyContext.dmg
import os.path

app = defines["app"]
notes = defines["notes"]
volicon = defines.get("volicon", "")

appname = os.path.basename(app)        # EasyContext.app
notesname = os.path.basename(notes)    # 安装说明（必读）.txt

# 体积/格式
format = "UDZO"
compression_level = 9

# 内容
files = [app, notes]
symlinks = {"Applications": "/Applications"}
if volicon:
    icon = volicon  # 挂载后磁盘卷图标

# 窗口与图标视图
background = "packaging/dmg-bg.png"
default_view = "icon-view"
window_rect = ((200, 120), (660, 545))
icon_size = 96
text_size = 12
icon_locations = {
    notesname: (330, 180),          # 安装说明在上、醒目
    appname: (175, 398),
    "Applications": (485, 398),
}
