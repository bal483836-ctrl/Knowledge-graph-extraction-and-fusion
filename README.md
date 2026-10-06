# Knowledge-graph-extraction-and-fusion

中药原型成分 – 肠道菌群 – 宿主基因/靶点 – 疾病 **相互作用网络**的知识图谱数据库设计。

本仓库给出把框架作用网络**具象化落地**为关系型数据库的 ER 方案，
并把 **肠道菌功能基因与酶** 设为后续深化重点。

## 目录

| 文件 | 说明 |
|---|---|
| [`docs/er-design/ER设计说明.md`](docs/er-design/ER设计说明.md) | **主文档**：建模思路、具象化落地三原则、实体/关系字典、框架图↔数据库对照、功能基因与酶深化规划、两张 ER 图 |
| [`docs/er-design/schema.sql`](docs/er-design/schema.sql) | 可直接建库的 PostgreSQL DDL（13 实体 + 10 关系表 + 索引 + 示例视图）|
| [`docs/er-design/diagrams/framework.mmd`](docs/er-design/diagrams/framework.mmd) | 概念去路图（Mermaid 源码）|
| [`docs/er-design/diagrams/er_diagram.mmd`](docs/er-design/diagrams/er_diagram.mmd) | 完整 ER 图（Mermaid 源码）|

## 一句话方法

> 把图里每一条"箭头/过程"升级成一张**带属性的关系表（关联实体）**，表里记录
> 方向 + 作用类型 + 发生条件 + 证据(PMID/方法/宿主) + 置信度；
> 最难的"菌把底物转化为代谢物"用核心反应表 `biotransformation` 把
> **谁(菌)·用什么(功能基因/酶)·把什么(底物)·变成什么(产物)** 绑到同一行。

## 快速建库

```bash
createdb tcm_gut_kg
psql -d tcm_gut_kg -f docs/er-design/schema.sql
```

## 在线查看 / 导出图

把 `*.mmd` 内容粘贴到 <https://mermaid.live> 即可渲染并导出 PNG/SVG。
（GitHub 也会直接渲染 `ER设计说明.md` 内嵌的 Mermaid 图。）
