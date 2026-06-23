# Web 设计规范（Vue 网页版）

> 仅适用于网页版。通用规范（颜色/字体/间距）见 [设计原则](design-system.md)。
>
> **修改网页任何样式前，必须查阅本文档。**

---

## ✍️ 字体规范（核心）

### 字体族

```css
font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
  'Helvetica Neue', Arial, 'PingFang SC', 'Microsoft YaHei', sans-serif;
```

已在 `src/style.css` 全局设置。

### 字号阶梯

| 元素 | 字号 | 行高 | 字重 | 颜色 | CSS 示例 |
|------|------|------|------|------|---------|
| **品牌"林立"** | 32px | 1.2 | 800 | `#FF6B35` | `.title { font-size: 32px; font-weight: 800; }` |
| **页面标题** | 28px | 1.3 | 800 | `#FF6B35` | `.title { font-size: 28px; }` |
| **区块标题** | 20px | 1.4 | 700 | `#333` | `h2 { font-size: 20px; font-weight: 700; }` |
| **卡片标题** | 18px | 1.4 | 600 | `#333` | — |
| **正文** | 15px | 1.6 | 400 | `#1a1a2e` | `body { font-size: 15px; }` |
| **辅助文字** | 14px | 1.5 | 400 | `#9E9E9E` | `.subtitle { font-size: 14px; color: #9e9e9e; }` |
| **Label** | 13px | 1.4 | 500 | `#666` | `.field label { font-size: 13px; font-weight: 500; }` |
| **按钮文字** | 15px | — | 600 | `#FFF`（主色背景）| `.btn-primary { font-size: 15px; font-weight: 600; }` |
| **最小文字** | 12px | 1.4 | 400 | `#9E9E9E` | 时间戳等 |

### 字重使用规则

```css
/* 400 Regular：正文默认 */
body { font-weight: 400; }

/* 500 Medium：表单 label、强调正文 */
.field label { font-weight: 500; }

/* 600 Semibold：按钮、卡片标题 */
.btn-primary, .card h3 { font-weight: 600; }

/* 700 Bold：区块标题 */
h2 { font-weight: 700; }

/* 800 Extrabold：品牌字样、登录页大标题 */
.brand { font-weight: 800; }
```

---

## 🎨 颜色使用规则

### 文字颜色

| 用途 | 颜色 | CSS |
|------|------|-----|
| 主要文字 | `#1a1a2e` | `color: #1a1a2e` |
| 次要文字 | `#333` | `color: #333` |
| 辅助/占位 | `#9e9e9e` | `color: #9e9e9e` |
| Label | `#666` | `color: #666` |
| 强调/链接 | `#FF6B35` | `color: #FF6B35` |
| 错误 | `#f44336` | `color: #f44336` |

### 背景颜色

| 元素 | 颜色 |
|------|------|
| 页面背景 | `#f5f5f5` |
| 卡片背景 | `#FFFFFF` |
| 输入框背景 | `#FFFFFF` |
| 浅灰区块（详情）| `#fafafa` |

---

## 📐 间距与尺寸

### 通用间距

```css
:root {
  --space-xs: 4px;
  --space-sm: 8px;
  --space-md: 12px;
  --space-lg: 16px;
  --space-xl: 24px;
  --space-2xl: 32px;
  --space-3xl: 48px;
}
```

### 卡片

| 属性 | 值 |
|------|-----|
| 圆角 | 12px（小卡片）/ 16px（大卡片）|
| 内边距 | 32px 24px（登录卡）/ 24px（普通卡）|
| 阴影 | `0 4px 24px rgba(0,0,0,0.06)`（登录）/ `0 2px 8px rgba(0,0,0,0.04)`（普通）|
| 最大宽度 | 380px（登录卡）/ 720px（内容区）|

### 输入框

```css
.field input {
  padding: 12px 14px;
  border: 1px solid #ddd;
  border-radius: 8px;
  font-size: 15px;
}
.field input:focus {
  border-color: #FF6B35;
  outline: none;
}
```

### 按钮

```css
/* 主按钮 */
.btn-primary {
  background: #FF6B35;
  color: white;
  border: none;
  padding: 14px;
  border-radius: 8px;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
}
.btn-primary:hover:not(:disabled) {
  background: #E55A2B;
}
.btn-primary:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
```

---

## 📱 响应式断点

| 断点 | 宽度 | 用途 |
|------|------|------|
| Mobile | < 640px | 单列布局 |
| Tablet | 640-1024px | 双列（预留）|
| Desktop | > 1024px | 居中 max-width 720px |

### 内容最大宽度

```css
.content {
  max-width: 720px;
  margin: 0 auto;
  padding: 0 24px;
}
```

---

## 🧩 组件规范

### 登录/注册卡片

```
┌────────────────────────────┐
│        林立（32px 橙）      │
│   记录你的每一次运动（14灰）│
│                            │
│  Label (13px 500)          │
│  [输入框              ]     │
│                            │
│  Label                     │
│  [输入框              ]     │
│                            │
│  [    登录（Filled）   ]    │
│                            │
│    还没有账号？立即注册     │
└────────────────────────────┘
```

- 背景 `#f5f5f5`，卡片居中
- 卡片宽 380px max-width
- 字段间距 16px
- 按钮距字段 8px

### 统计卡（详情页）

```
┌──────┬──────┬──────┬──────┐
│ 距离 │ 用时 │ 配速 │ 爬升 │
│ 5.0  │30:00│6'00" │ 120  │
│  km  │     │ /km  │  m   │
└──────┴──────┴──────┴──────┘
```

- 4 列等宽
- Label: 12px 灰
- 数字: 20px 700
- 单位: 12px 灰

---

## 🌙 暗色模式（规划中）

| 元素 | 亮色 | 暗色 |
|------|------|------|
| body 背景 | `#f5f5f5` | `#121212` |
| 卡片 | `#FFFFFF` | `#1E1E1E` |
| 文字主 | `#1a1a2e` | `#FFFFFF` |
| 文字辅 | `#9e9e9e` | `#757575` |
| 主色 | `#FF6B35` | `#FF6B35`（不变）|

> 用 CSS 变量 + `prefers-color-scheme` 实现。

---

## ✅ 样式检查清单

新增页面/组件时核对：

- [ ] 字号用了规范里的值（不随便写 px）
- [ ] 颜色用了规范里的值（不随便写 hex）
- [ ] 间距是 8 的倍数
- [ ] 输入框有 focus 态（橙色边框）
- [ ] 按钮有 hover / disabled 态
- [ ] 移动端可读（最小字号 12px）
- [ ] 内容区 max-width 720px 居中

---

## 📝 变更记录

| 日期 | 改动 |
|------|------|
| 2026-06-23 | 初版（从 LoginView.vue + style.css 提取）|
