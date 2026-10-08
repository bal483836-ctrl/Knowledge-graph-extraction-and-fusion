# ER设计第二方案

优先阅读[设计与评审.md](设计与评审.md)：包含对Claude原方案的评审、三条作用路径映射、功能基因与酶重点ER图、表字典、虚构入库案例及分阶段实施建议。

- [完整ER图.md](完整ER图.md)：38张表的物理结构。
- [schema.sql](schema.sql)：独立PostgreSQL schema，不覆盖原表。
- [acceptance.sql](acceptance.sql)：全部回滚的虚构案例与约束验收。
- [验证说明.md](验证说明.md)：已完成的静态检查、未执行的数据库和渲染验证。
- diagrams/：三张图的可编辑Mermaid源码。

先启动最小闭环，再补具体菌株基因、酶蛋白和反应证据。图谱连通不等于机制已证实。

- [queries.sql](queries.sql)：药源性候选路径及未知机制补全清单，返回每跳证据。
