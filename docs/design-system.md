# 设计原则（通用规范）

> **App 和 Web 通用**。颜色、字体、间距等基础 token，两端必须保持一致。
> 修改本文档后，同步更新 `linli-app/lib/app/theme.dart` 和 `linli-web/src/style.css`。

---

## 🎨 颜色系统

### 主色

| 名称 | 色值 | 用途 | App 引用 | Web 引用 |
|------|------|------|---------|---------|
| **主色 Primary** | `#FF6B35`（橙）| 按钮、强调、选中态、品牌 | `AppTheme.primaryOrange` | `#FF6B35` |
| **主色 Hover** | `#E55A2B` | 悬停态（Web）| — | `:hover` |
| **深蓝 Text** | `#1A1A2E` | 主要文字 | `AppTheme.darkBlue` | `#1a1a2e` |

### 中性色

| 名称 | 色值 | 用途 |
|------|------|------|
| **背景灰** | `#F5F5F5` | 页面背景 | `AppTheme.lightGray` |
| **中灰** | `#9E9E9E` | 辅助文字、未选中 | `AppTheme.mediumGray` |
| **白** | `#FFFFFF` | 卡片、AppBar 背景 | `Colors.white` |
| **边框** | `#DDDDDD` | 输入框边框等 | `#ddd` |
| **错误红** | `#F44336` | 错误提示 | `Colors.red` / `#f44336` |
| **成功绿** | `#4CAF50` | 成功提示（预留）| `#4caf50` |

### 暗色模式

| 元素 | 亮色 | 暗色 |
|------|------|------|
| 背景 | `#F5F5F5` | `#121212` |
| 卡片/AppBar | `#FFFFFF` | `#1E1E1E` |
| 未选中文字 | `#9E9E9E` | `#757575` |
| 主色 | `#FF6B35` | `#FF6B35`（保持不变）|

---

## ✍️ 字体

### 字体族

```
Apple System, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Microsoft YaHei", sans-serif
```

两端使用相同的字体栈，保证中文显示一致。

### 字号阶梯（App 用 sp，Web 用 px）

| 级别 | App (sp) | Web (px) | 字重 | 用途 |
|------|---------|---------|------|------|
| Display | 32 | 32 | 800 | 登录页"林立"标题 |
| H1 | 24 | 28 | 700 | 页面主标题 |
| H2 | 20 | 24 | 600 | 区块标题 |
| H3 | 18 | 20 | 600 | 卡片标题 |
| Body | 16 | 15 | 400 | 正文 |
| Body Small | 14 | 14 | 400 | 辅助文字、列表项 |
| Caption | 12 | 13 | 400 | 标签、时间戳、最弱文字 |
| Stat | 20 | 20 | 700 | 统计数字 |

### 字重约定

| 字重 | 用途 |
|------|------|
| 400 (Regular) | 正文 |
| 500 (Medium) | 输入框 label、强调正文 |
| 600 (Semibold) | 卡片标题、次要按钮 |
| 700 (Bold) | 页面标题、统计数字 |
| 800 (Extrabold) | 品牌"林立"字样 |

---

## 📏 间距系统（8 倍数）

| 名称 | 值 | 用途 |
|------|-----|------|
| **xs** | 4 | 图标与文字间距 |
| **sm** | 8 | 紧凑元素间距 |
| **md** | 12 | 表单字段间距 |
| **lg** | 16 | 标准内边距、卡片间距 |
| **xl** | 24 | 区块间距、页面边距 |
| **2xl** | 32 | 大区块间距 |
| **3xl** | 48 | 登录页元素间距 |

**页面通用边距**：左右 16-24（App 用 16，Web 用 24）

---

## 📐 圆角

| 元素 | 圆角 |
|------|------|
| 卡片 | 12 |
| 按钮 | 8 |
| 输入框 | 8 |
| 头像 | 圆形（50%）|
| 弹窗（BottomSheet）| 16（顶部）|

---

## 🌑 阴影 / 海拔

| 层级 | App elevation | 效果 |
|------|---------------|------|
| 卡片 | 1 | 轻微浮起 |
| AppBar | 0 | 无阴影（扁平）|
| FAB | 4 | 明显浮起 |
| 底部导航 | 8 | 最上层 |

---

## 🎯 图标规范

- **风格**：Material Design 图标（App 用 `Icons.*`，Web 用 Material Icons）
- **底部导航**：outline（未选中）/ filled（选中）
- **常用图标**：
  - 动态：`home` / `home_outlined`
  - 记录：`play_circle` / `play_circle_outlined`
  - 我的：`person` / `person_outlined`
  - 设置：`settings_outlined`
  - 点赞：`favorite` / `favorite_border`

---

## 📱 安全区

- **App**：所有页面用 `SafeArea` 包裹，避开状态栏/刘海
- **Web**：不需要（浏览器自动处理）

---

## 🔄 设计变更流程

1. 改 `design-system.md`（本文档）
2. 同步改代码：
   - App: `linli-app/lib/app/theme.dart`
   - Web: `linli-web/src/style.css` + 各组件 scoped style
3. 提交时注明：`docs: 更新设计规范 - XXX`
