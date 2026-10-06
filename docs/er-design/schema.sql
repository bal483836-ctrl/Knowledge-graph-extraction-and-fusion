-- =====================================================================
--  中药原型成分 - 肠道菌群 - 宿主靶点 - 疾病  知识图谱数据库
--  PostgreSQL DDL  (schema.sql)
-- ---------------------------------------------------------------------
--  设计原则：
--   1) N:M 关系一律用"中间关系表"；关系表 = 带证据(PMID/方法/宿主/置信度)的"断言行"。
--   2) 最难的"菌代谢底物 -> 产物"用 biotransformation 反应实体一次性落地，
--      一行绑定：底物 / 产物 / 菌 / 功能基因 / 酶。 (★FOCUS 枢纽)
--   3) 化学物只建一张 compound 表(InChIKey 唯一)，"原型/底物/代谢物"角色放在关系字段里。
--
--  建库：  createdb tcm_gut_kg && psql -d tcm_gut_kg -f schema.sql
-- =====================================================================

-- =====================================================================
--  A. 共享元数据 / 证据实体
-- =====================================================================

CREATE TABLE publication (            -- 文献 / 证据来源
    pub_id       BIGSERIAL PRIMARY KEY,
    pmid         VARCHAR(20) UNIQUE,            -- PubMed ID
    doi          VARCHAR(120),
    first_author VARCHAR(120),
    title        TEXT,
    journal      VARCHAR(200),
    year         INT,
    volume       VARCHAR(20),
    issue        VARCHAR(20),
    start_page   VARCHAR(20),
    end_page     VARCHAR(20),
    url          TEXT
);
COMMENT ON TABLE publication IS '文献/证据来源，被各关系表引用';

CREATE TABLE methodology (            -- 方法学 (借鉴 Disbiome Methodology)
    method_id         BIGSERIAL PRIMARY KEY,
    detection_method  VARCHAR(80),    -- 16S rRNA / 宏基因组 / 宏转录组 / 代谢组 / qPCR / 体外培养
    platform          VARCHAR(80),    -- Illumina / Nanopore / LC-MS ...
    sampling_location VARCHAR(80),    -- 采样部位: 粪便 / 盲肠内容物 / 血清 ...
    sampling_handling VARCHAR(120),
    sample_storage    VARCHAR(120),
    dna_extraction    VARCHAR(120)
);
COMMENT ON TABLE methodology IS '方法学(采样/检测手段)';

CREATE TABLE host (                   -- 宿主 / 实验体系 (对应框架"人+鼠")
    host_id   BIGSERIAL PRIMARY KEY,
    species   VARCHAR(40) NOT NULL,   -- human / mouse / rat ...
    model     VARCHAR(120),           -- C57BL/6 / germ-free无菌鼠 / 人源化菌群鼠 / SPF
    sex       VARCHAR(10),
    age_range VARCHAR(40),
    diet      VARCHAR(120),
    condition VARCHAR(120)            -- 健康 / 某疾病模型
);
COMMENT ON TABLE host IS '宿主/实验体系，对应框架"人+鼠"';


-- =====================================================================
--  B. 中药与化学物
-- =====================================================================

CREATE TABLE herb_category (          -- 中药分类 (自引用, 对标 TCMSP InfoChild)
    category_id BIGSERIAL PRIMARY KEY,
    cn_name     VARCHAR(120),
    en_name     VARCHAR(120),
    parent_id   BIGINT REFERENCES herb_category(category_id)
);
COMMENT ON TABLE herb_category IS '中药分类(自引用层级)';

CREATE TABLE herb (                   -- 中药 (对标 TCMSP InfoHerb)
    herb_id     BIGSERIAL PRIMARY KEY,
    cn_name     VARCHAR(120) NOT NULL,
    pinyin      VARCHAR(120),
    latin_name  VARCHAR(200),
    en_name     VARCHAR(200),
    family      VARCHAR(120),         -- 科
    part_used   VARCHAR(120),         -- 药用部位
    property    VARCHAR(120),         -- 性味(可选)
    meridian    VARCHAR(120),         -- 归经(可选)
    category_id BIGINT REFERENCES herb_category(category_id)
);
COMMENT ON TABLE herb IS '中药';

CREATE TABLE compound (               -- 化合物 / 原型成分 (统一化学实体, 对标 TCMSP InfoMolecule)
    compound_id      BIGSERIAL PRIMARY KEY,
    name             VARCHAR(255) NOT NULL,
    synonyms         TEXT,
    formula          VARCHAR(120),
    mw               NUMERIC,         -- 分子量
    smiles           TEXT,
    inchikey         VARCHAR(27) UNIQUE,    -- ★跨库唯一匹配键
    pubchem_cid      VARCHAR(20),
    cas              VARCHAR(20),
    chebi_id         VARCHAR(20),
    super_class      VARCHAR(120),    -- 结构大类
    chem_class       VARCHAR(120),    -- 结构小类
    is_tcm_prototype BOOLEAN DEFAULT FALSE, -- 是否作为中药原型成分出现
    -- ADMET (借鉴 TCMSP)
    ob               NUMERIC,         -- 口服生物利用度
    caco2            NUMERIC,         -- Caco-2 肠上皮透过性
    bbb              NUMERIC,         -- 血脑屏障透过性
    drug_likeness    NUMERIC,         -- 类药性
    halflife         NUMERIC,         -- 半衰期
    hdon             INT,             -- 氢键供体数
    hacc             INT,             -- 氢键受体数
    tpsa             NUMERIC,         -- 拓扑极性表面积
    rbn              INT,             -- 可旋转键数
    alogp            NUMERIC
);
COMMENT ON TABLE compound IS '化合物/原型成分(统一化学实体)；角色(原型/底物/代谢物)放在关系表字段中';
COMMENT ON COLUMN compound.inchikey IS '跨库唯一匹配键，建议作主要去重依据';


-- =====================================================================
--  C. 肠道菌群 - 功能基因 - 酶   (★FOCUS 深化脊柱)
-- =====================================================================

CREATE TABLE microbe (                -- 微生物 / 菌 (含分类层级, 对标 Disbiome Organism)
    microbe_id         BIGSERIAL PRIMARY KEY,
    scientific_name    VARCHAR(255) NOT NULL,
    ncbi_taxon_id      VARCHAR(20) UNIQUE,     -- NCBI Taxonomy ID
    silva_id           VARCHAR(40),
    gtdb_id            VARCHAR(80),
    rank               VARCHAR(20)             -- 门/纲/目/科/属/种/株
        CHECK (rank IN ('phylum','class','order','family','genus','species','strain')),
    parent_taxon_id    BIGINT REFERENCES microbe(microbe_id),  -- 分类上级(自引用)
    phylum             VARCHAR(120),
    gram_stain         VARCHAR(20),
    oxygen_requirement VARCHAR(30)             -- aerobe / anaerobe / facultative
);
COMMENT ON TABLE microbe IS '微生物/菌(含分类层级,自引用)';

CREATE TABLE genome (                 -- 细菌基因组 (★FOCUS)
    genome_id           BIGSERIAL PRIMARY KEY,
    microbe_id          BIGINT NOT NULL REFERENCES microbe(microbe_id),
    assembly_accession  VARCHAR(40),            -- NCBI / GTDB assembly
    strain_name         VARCHAR(120),
    genome_size_bp      BIGINT,
    completeness        NUMERIC,
    contamination       NUMERIC,
    source              VARCHAR(80)
);
COMMENT ON TABLE genome IS '细菌基因组，把功能基因绑定到具体菌株';

CREATE TABLE functional_gene (        -- 功能基因 / 基因簇 (★★FOCUS 重点)
    gene_id             BIGSERIAL PRIMARY KEY,
    genome_id           BIGINT REFERENCES genome(genome_id),    -- 可空:KO/泛基因组层
    microbe_id          BIGINT REFERENCES microbe(microbe_id),  -- 只知菌不知基因组时
    gene_symbol         VARCHAR(120),
    product_description TEXT,
    ko_id               VARCHAR(20),            -- KEGG Ortholog
    cog_id              VARCHAR(20),
    pfam_id             VARCHAR(20),
    cazy_family         VARCHAR(40),            -- 碳水化合物活性酶家族
    tcdb_id             VARCHAR(40),            -- 转运蛋白
    is_cluster          BOOLEAN DEFAULT FALSE,  -- 是否基因簇/BGC
    cluster_type        VARCHAR(80),            -- antiSMASH / gutSMASH 类别
    locus_tag           VARCHAR(80),
    annotation_source   VARCHAR(80),
    annotation_evidence VARCHAR(20)             -- predicted(预测) / experimental(实验)
        CHECK (annotation_evidence IN ('predicted','experimental'))
);
COMMENT ON TABLE functional_gene IS '功能基因/基因簇 —— 后续完善的承重墙之一';

CREATE TABLE enzyme (                 -- 酶 (★★FOCUS 重点)
    enzyme_id      BIGSERIAL PRIMARY KEY,
    name           VARCHAR(255),
    ec_number      VARCHAR(20),                 -- EC 号
    enzyme_class   VARCHAR(40),                 -- 氧化还原酶/转移酶/水解酶/裂合酶/异构酶/连接酶/易位酶
    reaction_family VARCHAR(120),               -- 如 BSH(胆盐水解酶)/偶氮还原酶/β-葡萄糖醛酸酶/GH 家族
    cofactor       VARCHAR(120)
    -- 预留: km, kcat, substrate_specificity 供后续精细化
);
COMMENT ON TABLE enzyme IS '酶 —— 后续完善的承重墙之一';


-- =====================================================================
--  D. 宿主靶点 - 通路 - 疾病
-- =====================================================================

CREATE TABLE host_target (            -- 宿主基因 / 靶点 (对标 TCMSP InfoTarget)
    target_id   BIGSERIAL PRIMARY KEY,
    name        VARCHAR(255),
    gene_symbol VARCHAR(80),
    uniprot_id  VARCHAR(20),
    entrez_id   VARCHAR(20),
    ensembl_id  VARCHAR(40),
    organism    VARCHAR(20)                     -- human / mouse (对应框架"人+鼠")
        CHECK (organism IN ('human','mouse','rat','other')),
    target_type VARCHAR(40),                    -- 蛋白/受体/酶/转录因子/通路节点
    drugbank_id VARCHAR(20)
);
COMMENT ON TABLE host_target IS '宿主基因/靶点(人+鼠)';

CREATE TABLE pathway (                -- 信号通路 (可选)
    pathway_id  BIGSERIAL PRIMARY KEY,
    name        VARCHAR(255),
    source      VARCHAR(40),                    -- KEGG / Reactome / WikiPathways
    external_id VARCHAR(40)
);
COMMENT ON TABLE pathway IS '信号通路(可选)';

CREATE TABLE disease (                -- 疾病 (对标 TCMSP InfoDisease + Disbiome Disease)
    disease_id   BIGSERIAL PRIMARY KEY,
    name         VARCHAR(255) NOT NULL,
    abbreviation VARCHAR(40),
    icd9         VARCHAR(20),
    icd10        VARCHAR(20),
    mesh_id      VARCHAR(20),
    do_id        VARCHAR(20),                   -- Disease Ontology
    meddra_id    VARCHAR(20),                   -- MedDRA (Disbiome 标准化)
    stage        VARCHAR(80)
);
COMMENT ON TABLE disease IS '疾病';


-- =====================================================================
--  E. 关系 / 关联实体  (每张 = 带证据的断言表)
-- =====================================================================

-- --- 基础: 中药-成分 ---
CREATE TABLE herb_compound (
    herb_id     BIGINT NOT NULL REFERENCES herb(herb_id),
    compound_id BIGINT NOT NULL REFERENCES compound(compound_id),
    content     VARCHAR(80),          -- 含量(可选)
    part        VARCHAR(80),
    pub_id      BIGINT REFERENCES publication(pub_id),
    PRIMARY KEY (herb_id, compound_id)
);
COMMENT ON TABLE herb_compound IS '中药-成分 (N:M)';

-- --- ★FOCUS: 功能基因-酶 (基因编码酶) ---
CREATE TABLE gene_enzyme (
    gene_id             BIGINT NOT NULL REFERENCES functional_gene(gene_id),
    enzyme_id           BIGINT NOT NULL REFERENCES enzyme(enzyme_id),
    relation            VARCHAR(20) DEFAULT 'encodes',
    annotation_evidence VARCHAR(20)
        CHECK (annotation_evidence IN ('predicted','experimental')),
    pub_id              BIGINT REFERENCES publication(pub_id),
    PRIMARY KEY (gene_id, enzyme_id)
);
COMMENT ON TABLE gene_enzyme IS '功能基因-酶 编码关系 (N:M) ★FOCUS';

-- --- ★★核心枢纽: 生物转化反应 (路线②③代谢段一次性落地) ---
CREATE TABLE biotransformation (
    rxn_id               BIGSERIAL PRIMARY KEY,
    substrate_compound_id BIGINT NOT NULL REFERENCES compound(compound_id), -- 底物
    product_compound_id   BIGINT NOT NULL REFERENCES compound(compound_id), -- 产物
    microbe_id           BIGINT REFERENCES microbe(microbe_id),            -- 催化菌
    gene_id              BIGINT REFERENCES functional_gene(gene_id),       -- ★功能基因/基因簇
    enzyme_id            BIGINT REFERENCES enzyme(enzyme_id),              -- ★酶
    substrate_role       VARCHAR(20)      -- 底物角色
        CHECK (substrate_role IN ('drug_substrate','endogenous','exogenous')),
    product_role         VARCHAR(20)      -- 产物角色
        CHECK (product_role IN ('drug_derived','endogenous','exogenous')),
    reaction_type        VARCHAR(80),     -- 水解/还原/氧化/脱羧/去糖基化/脱羟基/差向异构…
    ec_number            VARCHAR(20),     -- 冗余缓存便于查询
    evidence_type        VARCHAR(20)      -- 证据类型
        CHECK (evidence_type IN ('in_vitro','in_vivo','in_silico','clinical')),
    conditions           TEXT,
    host_id              BIGINT REFERENCES host(host_id),
    method_id            BIGINT REFERENCES methodology(method_id),
    pub_id               BIGINT REFERENCES publication(pub_id),
    confidence           NUMERIC          -- 0~1
);
COMMENT ON TABLE biotransformation IS
 '★★核心枢纽: 一行绑定 底物/产物/菌/功能基因/酶; 服务路线②(转化原型成分→药源性代谢物)与路线③的代谢段';
COMMENT ON COLUMN biotransformation.substrate_role IS 'drug_substrate=药源性底物, endogenous=内源, exogenous=外源';
COMMENT ON COLUMN biotransformation.product_role   IS 'drug_derived=药源性代谢物, endogenous=内源, exogenous=外源';

-- --- 化合物-靶点作用 (路线①②③共同收口) ---
CREATE TABLE compound_target (
    ct_id            BIGSERIAL PRIMARY KEY,
    compound_id      BIGINT NOT NULL REFERENCES compound(compound_id),
    target_id        BIGINT NOT NULL REFERENCES host_target(target_id),
    compound_role    VARCHAR(30)          -- 作用物此刻的角色
        CHECK (compound_role IN ('prototype_direct','drug_derived_metabolite','microbial_metabolite')),
    action_type      VARCHAR(30),         -- 激动/拮抗/抑制/调节/结合
    action_route     VARCHAR(30)          -- 发生方式(捕捉路线①两条子路径)
        CHECK (action_route IN ('absorbed_blood','local_gut','via_metabolite')),
    effect_direction VARCHAR(20),         -- 上调/下调/激活/抑制
    assay_type       VARCHAR(80),
    validated        BOOLEAN DEFAULT FALSE,-- 实验验证 (借鉴 TCMSP)
    evidence_type    VARCHAR(20)
        CHECK (evidence_type IN ('in_vitro','in_vivo','in_silico','clinical')),
    host_id          BIGINT REFERENCES host(host_id),
    method_id        BIGINT REFERENCES methodology(method_id),
    pub_id           BIGINT REFERENCES publication(pub_id),
    confidence       NUMERIC
);
COMMENT ON TABLE compound_target IS
 '化合物-宿主靶点作用 (N:M); compound_role 区分 原型直接/药源性代谢物/微生物代谢物, 统一三条路线收口';
COMMENT ON COLUMN compound_target.action_route IS 'absorbed_blood=吸收入血, local_gut=肠道局部, via_metabolite=经代谢物';

-- --- 靶点-疾病 ---
CREATE TABLE target_disease (
    td_id      BIGSERIAL PRIMARY KEY,
    target_id  BIGINT NOT NULL REFERENCES host_target(target_id),
    disease_id BIGINT NOT NULL REFERENCES disease(disease_id),
    relation   VARCHAR(40),              -- 致病/治疗靶点/生物标志物/保护
    direction  VARCHAR(40),             -- 上调致病/下调治疗 …
    host_id    BIGINT REFERENCES host(host_id),
    pub_id     BIGINT REFERENCES publication(pub_id),
    confidence NUMERIC
);
COMMENT ON TABLE target_disease IS '靶点-疾病 (N:M)';

-- --- 靶点-通路 (可选) ---
CREATE TABLE target_pathway (
    target_id  BIGINT NOT NULL REFERENCES host_target(target_id),
    pathway_id BIGINT NOT NULL REFERENCES pathway(pathway_id),
    role       VARCHAR(40),
    pub_id     BIGINT REFERENCES publication(pub_id),
    PRIMARY KEY (target_id, pathway_id)
);
COMMENT ON TABLE target_pathway IS '靶点-通路 (N:M, 可选)';

-- --- 成分-菌 丰度调控 (路线③「促进或抑制特定菌」, 类比 Disbiome Experiment) ---
CREATE TABLE compound_microbe (
    cm_id            BIGSERIAL PRIMARY KEY,
    compound_id      BIGINT NOT NULL REFERENCES compound(compound_id),
    microbe_id       BIGINT NOT NULL REFERENCES microbe(microbe_id),
    effect           VARCHAR(20)          -- 促进/抑制/无影响
        CHECK (effect IN ('promote','inhibit','no_effect')),
    abundance_change VARCHAR(20)          -- 上升/下降/不变
        CHECK (abundance_change IN ('increase','decrease','unchanged')),
    fold_change      NUMERIC,
    p_value          NUMERIC,
    mechanism        VARCHAR(120),        -- 直接抑菌/选择性富集/底物供给…
    host_id          BIGINT REFERENCES host(host_id),
    method_id        BIGINT REFERENCES methodology(method_id),
    pub_id           BIGINT REFERENCES publication(pub_id),
    confidence       NUMERIC
);
COMMENT ON TABLE compound_microbe IS '成分-菌 丰度调控 (路线③「促进或抑制特定菌」)';

-- --- 菌-菌 交叉喂养/竞争 (路线③「底物利用与交叉喂养」, 自引用) ---
CREATE TABLE microbe_interaction (
    mi_id                 BIGSERIAL PRIMARY KEY,
    microbe_a_id          BIGINT NOT NULL REFERENCES microbe(microbe_id),
    microbe_b_id          BIGINT NOT NULL REFERENCES microbe(microbe_id),
    interaction_type      VARCHAR(30)     -- 交叉喂养/竞争/互养
        CHECK (interaction_type IN ('cross_feeding','competition','syntrophy','other')),
    exchanged_compound_id BIGINT REFERENCES compound(compound_id),  -- 交换的底物/代谢物
    direction             VARCHAR(20),    -- a_to_b / b_to_a / mutual
    pub_id                BIGINT REFERENCES publication(pub_id),
    confidence            NUMERIC
);
COMMENT ON TABLE microbe_interaction IS '菌-菌 交叉喂养/竞争 (路线③「底物利用与交叉喂养」)';

-- --- 菌-疾病 关联 (整合 Disbiome, 交叉验证) ---
CREATE TABLE microbe_disease (
    md_id      BIGSERIAL PRIMARY KEY,
    microbe_id BIGINT NOT NULL REFERENCES microbe(microbe_id),
    disease_id BIGINT NOT NULL REFERENCES disease(disease_id),
    direction  VARCHAR(20)               -- 疾病中富集/减少
        CHECK (direction IN ('enriched','depleted','unchanged')),
    host_id    BIGINT REFERENCES host(host_id),
    method_id  BIGINT REFERENCES methodology(method_id),
    pub_id     BIGINT REFERENCES publication(pub_id),
    confidence NUMERIC
);
COMMENT ON TABLE microbe_disease IS '菌-疾病 关联 (整合 Disbiome)';

-- --- ★FOCUS 扩展: 成分对菌功能基因/酶的调控 (路线③深机制) ---
CREATE TABLE compound_enzyme_modulation (
    cem_id      BIGSERIAL PRIMARY KEY,
    compound_id BIGINT NOT NULL REFERENCES compound(compound_id),
    enzyme_id   BIGINT REFERENCES enzyme(enzyme_id),
    gene_id     BIGINT REFERENCES functional_gene(gene_id),
    effect      VARCHAR(20)              -- 诱导/抑制(表达或活性)
        CHECK (effect IN ('induce','inhibit')),
    target_level VARCHAR(20)            -- expression(表达) / activity(活性)
        CHECK (target_level IN ('expression','activity')),
    pub_id      BIGINT REFERENCES publication(pub_id),
    confidence  NUMERIC,
    CHECK (enzyme_id IS NOT NULL OR gene_id IS NOT NULL)  -- 至少指向酶或基因之一
);
COMMENT ON TABLE compound_enzyme_modulation IS
 '成分对菌功能基因/酶的调控 (路线③深机制: 成分改变菌的"功能"而非仅"丰度") ★FOCUS 扩展';


-- =====================================================================
--  F. 索引
-- =====================================================================
CREATE INDEX idx_compound_inchikey      ON compound(inchikey);
CREATE INDEX idx_microbe_taxon          ON microbe(ncbi_taxon_id);
CREATE INDEX idx_gene_ko                ON functional_gene(ko_id);
CREATE INDEX idx_enzyme_ec              ON enzyme(ec_number);

CREATE INDEX idx_bt_substrate           ON biotransformation(substrate_compound_id);
CREATE INDEX idx_bt_product             ON biotransformation(product_compound_id);
CREATE INDEX idx_bt_microbe             ON biotransformation(microbe_id);
CREATE INDEX idx_bt_gene                ON biotransformation(gene_id);
CREATE INDEX idx_bt_enzyme              ON biotransformation(enzyme_id);

CREATE INDEX idx_ct_compound            ON compound_target(compound_id);
CREATE INDEX idx_ct_target              ON compound_target(target_id);
CREATE INDEX idx_td_target              ON target_disease(target_id);
CREATE INDEX idx_td_disease             ON target_disease(disease_id);
CREATE INDEX idx_cm_compound            ON compound_microbe(compound_id);
CREATE INDEX idx_cm_microbe             ON compound_microbe(microbe_id);
CREATE INDEX idx_md_microbe             ON microbe_disease(microbe_id);
CREATE INDEX idx_md_disease             ON microbe_disease(disease_id);


-- =====================================================================
--  G. 示例视图
-- =====================================================================

-- G1. ★FOCUS 脊柱: 菌 -> 基因组 -> 功能基因 -> 酶  (一览每种菌的功能基因与酶)
CREATE VIEW v_microbe_gene_enzyme AS
SELECT m.microbe_id,
       m.scientific_name,
       g.strain_name,
       fg.gene_id,
       fg.gene_symbol,
       fg.ko_id,
       fg.is_cluster,
       e.enzyme_id,
       e.name        AS enzyme_name,
       e.ec_number,
       e.reaction_family
FROM microbe m
LEFT JOIN genome g           ON g.microbe_id = m.microbe_id
LEFT JOIN functional_gene fg ON fg.genome_id = g.genome_id OR fg.microbe_id = m.microbe_id
LEFT JOIN gene_enzyme ge     ON ge.gene_id = fg.gene_id
LEFT JOIN enzyme e           ON e.enzyme_id = ge.enzyme_id;
COMMENT ON VIEW v_microbe_gene_enzyme IS '★FOCUS 脊柱: 菌→基因组→功能基因→酶 一览';

-- G2. 路线②全链: 原型成分 --菌/基因/酶--> 药源性代谢物 --> 靶点 --> 疾病
CREATE VIEW v_route2_prototype_to_disease AS
SELECT sub.name              AS prototype_compound,
       m.scientific_name     AS microbe,
       fg.gene_symbol        AS gene,
       e.ec_number           AS enzyme_ec,
       prod.name             AS drug_derived_metabolite,
       t.gene_symbol         AS host_target,
       d.name                AS disease,
       bt.pub_id             AS reaction_pub,
       ct.pub_id             AS action_pub
FROM biotransformation bt
JOIN compound sub            ON sub.compound_id = bt.substrate_compound_id AND sub.is_tcm_prototype
JOIN compound prod           ON prod.compound_id = bt.product_compound_id
LEFT JOIN microbe m          ON m.microbe_id = bt.microbe_id
LEFT JOIN functional_gene fg ON fg.gene_id = bt.gene_id
LEFT JOIN enzyme e           ON e.enzyme_id = bt.enzyme_id
JOIN compound_target ct      ON ct.compound_id = prod.compound_id
                            AND ct.compound_role = 'drug_derived_metabolite'
JOIN host_target t           ON t.target_id = ct.target_id
JOIN target_disease td       ON td.target_id = t.target_id
JOIN disease d               ON d.disease_id = td.disease_id
WHERE bt.substrate_role = 'drug_substrate'
  AND bt.product_role   = 'drug_derived';
COMMENT ON VIEW v_route2_prototype_to_disease IS '路线②全链: 原型成分→(菌/基因/酶)→药源性代谢物→靶点→疾病';
