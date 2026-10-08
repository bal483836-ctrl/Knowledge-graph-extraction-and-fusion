-- PostgreSQL 15+; 独立方案，不覆盖 Claude 原表。首次执行；失败整体回滚。
BEGIN;
CREATE SCHEMA tcm_er_v2;
SET LOCAL search_path TO tcm_er_v2, public;

-- 化合物
CREATE TABLE compound (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  inchikey varchar(27) UNIQUE,
  identity_status text NOT NULL CHECK (identity_status IN ('exact','partial','unresolved'))
);
COMMENT ON TABLE compound IS '化合物';

-- 中药
CREATE TABLE herb (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  medicinal_part text,
  processing text
);
COMMENT ON TABLE herb IS '中药';

-- 微生物分类单元
CREATE TABLE taxon (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  rank text NOT NULL,
  ncbi_taxid bigint UNIQUE,
  parent_id bigint REFERENCES taxon(id)
);
COMMENT ON TABLE taxon IS '微生物分类单元';

-- 菌株或MAG归属
CREATE TABLE strain (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  taxon_id bigint NOT NULL REFERENCES taxon(id),
  name text NOT NULL,
  accession text UNIQUE
);
COMMENT ON TABLE strain IS '菌株或MAG归属';

-- 基因组装版本
CREATE TABLE genome (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  strain_id bigint NOT NULL REFERENCES strain(id),
  assembly_version text NOT NULL UNIQUE,
  completeness numeric CHECK (completeness BETWEEN 0 AND 100),
  contamination numeric CHECK (contamination BETWEEN 0 AND 100)
);
COMMENT ON TABLE genome IS '基因组装版本';

-- 具体微生物基因
CREATE TABLE microbial_gene (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  genome_id bigint NOT NULL REFERENCES genome(id),
  locus_tag text NOT NULL,
  sequence_accession text,
  UNIQUE(genome_id,locus_tag)
);
COMMENT ON TABLE microbial_gene IS '具体微生物基因';

-- 基因簇
CREATE TABLE gene_cluster (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  genome_id bigint NOT NULL REFERENCES genome(id),
  name text NOT NULL,
  UNIQUE(id,genome_id)
);
COMMENT ON TABLE gene_cluster IS '基因簇';

-- 簇成员
CREATE TABLE cluster_member (
  cluster_id bigint NOT NULL REFERENCES gene_cluster(id),
  gene_id bigint NOT NULL REFERENCES microbial_gene(id),
  PRIMARY KEY(cluster_id,gene_id)
);
COMMENT ON TABLE cluster_member IS '簇成员';

-- 具体微生物蛋白含酶
CREATE TABLE protein (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  uniprot_accession text UNIQUE,
  sequence_accession text,
  strain_id bigint REFERENCES strain(id)
);
COMMENT ON TABLE protein IS '具体微生物蛋白含酶';

-- 功能类别KO EC Pfam CAZy
CREATE TABLE functional_term (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  namespace text NOT NULL,
  accession text NOT NULL,
  release text NOT NULL,
  name text,
  UNIQUE(namespace,accession,release)
);
COMMENT ON TABLE functional_term IS '功能类别KO EC Pfam CAZy';

-- 宿主基因
CREATE TABLE host_gene (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  host_taxid bigint NOT NULL,
  symbol text NOT NULL,
  gene_accession text NOT NULL,
  UNIQUE(host_taxid,gene_accession)
);
COMMENT ON TABLE host_gene IS '宿主基因';

-- 宿主蛋白或复合物靶点
CREATE TABLE host_target (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  host_taxid bigint NOT NULL,
  name text NOT NULL,
  kind text NOT NULL CHECK(kind IN ('protein','complex')),
  accession text,
  UNIQUE(host_taxid,accession)
);
COMMENT ON TABLE host_target IS '宿主蛋白或复合物靶点';

-- 宿主基因产物
CREATE TABLE host_gene_product (
  gene_id bigint NOT NULL REFERENCES host_gene(id),
  target_id bigint NOT NULL REFERENCES host_target(id),
  PRIMARY KEY(gene_id,target_id)
);
COMMENT ON TABLE host_gene_product IS '宿主基因产物';

-- 疾病
CREATE TABLE disease (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  ontology text NOT NULL,
  accession text NOT NULL,
  UNIQUE(ontology,accession)
);
COMMENT ON TABLE disease IS '疾病';

-- 文献或数据库记录
CREATE TABLE source_record (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind text NOT NULL CHECK(kind IN ('publication','database','synthetic')),
  locator text NOT NULL,
  version text NOT NULL,
  title text,
  url text,
  UNIQUE(kind,locator,version)
);
COMMENT ON TABLE source_record IS '文献或数据库记录';

-- 实验或分析
CREATE TABLE experiment (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_id bigint NOT NULL REFERENCES source_record(id),
  local_key text NOT NULL,
  system text NOT NULL CHECK(system IN ('human','animal','culture','purified_enzyme','computational','unspecified')),
  host_taxid bigint,
  model text,
  disease_id bigint REFERENCES disease(id),
  UNIQUE(source_id,local_key)
);
COMMENT ON TABLE experiment IS '实验或分析';

-- 实验组对照组
CREATE TABLE study_arm (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  experiment_id bigint NOT NULL REFERENCES experiment(id),
  name text NOT NULL,
  n integer CHECK(n>0),
  is_control boolean NOT NULL,
  UNIQUE(id,experiment_id)
);
COMMENT ON TABLE study_arm IS '实验组对照组';

-- 干预剂量
CREATE TABLE exposure (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  arm_id bigint NOT NULL REFERENCES study_arm(id),
  compound_id bigint NOT NULL REFERENCES compound(id),
  dose numeric,
  dose_unit text,
  route text,
  duration text,
  CHECK ((dose IS NULL) = (dose_unit IS NULL))
);
COMMENT ON TABLE exposure IS '干预剂量';

-- 样本时间方法
CREATE TABLE context (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  experiment_id bigint NOT NULL REFERENCES experiment(id),
  sample_accession text,
  site text,
  timepoint text,
  method text NOT NULL,
  conditions jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE(id,experiment_id)
);
COMMENT ON TABLE context IS '样本时间方法';

-- 证据观察
CREATE TABLE observation (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  experiment_id bigint NOT NULL REFERENCES experiment(id),
  context_id bigint,
  subject_arm_id bigint,
  control_arm_id bigint,
  endpoint text NOT NULL,
  metric text NOT NULL,
  direction text NOT NULL CHECK(direction IN ('increase','decrease','unchanged','detected','not_detected','unknown')),
  value numeric,
  unit text,
  p_value numeric CHECK(p_value BETWEEN 0 AND 1),
  q_value numeric CHECK(q_value BETWEEN 0 AND 1),
  evidence_method text NOT NULL,
  quote text NOT NULL,
  location text NOT NULL,
  review_status text NOT NULL DEFAULT 'pending' CHECK(review_status IN ('pending','accepted','rejected')),
  extraction_version text NOT NULL,
  FOREIGN KEY(context_id,experiment_id) REFERENCES context(id,experiment_id),
  FOREIGN KEY(subject_arm_id,experiment_id) REFERENCES study_arm(id,experiment_id),
  FOREIGN KEY(control_arm_id,experiment_id) REFERENCES study_arm(id,experiment_id),
  CHECK(subject_arm_id IS NULL OR control_arm_id IS NULL OR subject_arm_id<>control_arm_id)
);
COMMENT ON TABLE observation IS '证据观察';

-- 化学反应定义
CREATE TABLE reaction (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  rhea_id text UNIQUE,
  direction text NOT NULL CHECK(direction IN ('forward','reversible','unknown')),
  completeness text NOT NULL CHECK(completeness IN ('partial','balanced'))
);
COMMENT ON TABLE reaction IS '化学反应定义';

-- 多底物多产物
CREATE TABLE reaction_participant (
  reaction_id bigint NOT NULL REFERENCES reaction(id),
  compound_id bigint NOT NULL REFERENCES compound(id),
  side text NOT NULL CHECK(side IN ('substrate','product')),
  stoichiometry numeric CHECK(stoichiometry>0),
  compartment text NOT NULL DEFAULT 'unknown',
  PRIMARY KEY(reaction_id,compound_id,side,compartment)
);
COMMENT ON TABLE reaction_participant IS '多底物多产物';

-- 某实验的转化观察
CREATE TABLE transformation (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reaction_id bigint NOT NULL REFERENCES reaction(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  substrate_origin text NOT NULL CHECK(substrate_origin IN ('drug','host','diet','other','unknown')),
  product_origin text NOT NULL CHECK(product_origin IN ('drug_derived','other','unknown')),
  attribution text NOT NULL CHECK(attribution IN ('community','taxon','strain','protein','unknown'))
);
COMMENT ON TABLE transformation IS '某实验的转化观察';

-- 多菌多酶参与者
CREATE TABLE transformation_actor (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  transformation_id bigint NOT NULL REFERENCES transformation(id),
  taxon_id bigint REFERENCES taxon(id),
  strain_id bigint REFERENCES strain(id),
  protein_id bigint REFERENCES protein(id),
  role text NOT NULL CHECK(role IN ('tested','catalyst_candidate','catalyst_validated')),
  CHECK(num_nonnulls(taxon_id,strain_id,protein_id)=1)
);
COMMENT ON TABLE transformation_actor IS '多菌多酶参与者';

-- 中药含成分
CREATE TABLE herb_compound (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  herb_id bigint NOT NULL REFERENCES herb(id),
  compound_id bigint NOT NULL REFERENCES compound(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  role text NOT NULL CHECK(role IN ('prototype','other','unknown'))
);
COMMENT ON TABLE herb_compound IS '中药含成分';

-- 基因编码蛋白
CREATE TABLE gene_product (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  gene_id bigint NOT NULL REFERENCES microbial_gene(id),
  protein_id bigint NOT NULL REFERENCES protein(id),
  observation_id bigint NOT NULL REFERENCES observation(id)
);
COMMENT ON TABLE gene_product IS '基因编码蛋白';

-- 基因功能注释
CREATE TABLE gene_annotation (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  gene_id bigint NOT NULL REFERENCES microbial_gene(id),
  term_id bigint NOT NULL REFERENCES functional_term(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  assignment text NOT NULL CHECK(assignment IN ('predicted','experimental'))
);
COMMENT ON TABLE gene_annotation IS '基因功能注释';

-- 蛋白功能注释
CREATE TABLE protein_annotation (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  protein_id bigint NOT NULL REFERENCES protein(id),
  term_id bigint NOT NULL REFERENCES functional_term(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  assignment text NOT NULL CHECK(assignment IN ('predicted','experimental'))
);
COMMENT ON TABLE protein_annotation IS '蛋白功能注释';

-- 酶催化反应
CREATE TABLE protein_reaction (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  protein_id bigint NOT NULL REFERENCES protein(id),
  reaction_id bigint NOT NULL REFERENCES reaction(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  assignment text NOT NULL CHECK(assignment IN ('predicted','experimental'))
);
COMMENT ON TABLE protein_reaction IS '酶催化反应';

-- 化合物靶点作用
CREATE TABLE compound_target (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  compound_id bigint NOT NULL REFERENCES compound(id),
  target_id bigint NOT NULL REFERENCES host_target(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  action text NOT NULL CHECK(action IN ('binds','activates','inhibits','indirect_modulation','unknown')), route text NOT NULL CHECK(route IN ('blood','local_gut','unknown'))
);
COMMENT ON TABLE compound_target IS '化合物靶点作用';

-- 化合物调控宿主基因
CREATE TABLE compound_host_gene (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  compound_id bigint NOT NULL REFERENCES compound(id),
  gene_id bigint NOT NULL REFERENCES host_gene(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  action text NOT NULL CHECK(action IN ('expression_increase','expression_decrease','unknown'))
);
COMMENT ON TABLE compound_host_gene IS '化合物调控宿主基因';

-- 靶点疾病关联
CREATE TABLE target_disease (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id bigint NOT NULL REFERENCES host_target(id),
  disease_id bigint NOT NULL REFERENCES disease(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  relation text NOT NULL CHECK(relation IN ('associated','causal','protective','biomarker','therapeutic_candidate'))
);
COMMENT ON TABLE target_disease IS '靶点疾病关联';

-- 菌疾病关联
CREATE TABLE microbe_disease (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  taxon_id bigint NOT NULL REFERENCES taxon(id),
  disease_id bigint NOT NULL REFERENCES disease(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  relation text NOT NULL CHECK(relation IN ('associated','causal','unknown'))
);
COMMENT ON TABLE microbe_disease IS '菌疾病关联';

-- 成分菌变化
CREATE TABLE compound_microbe (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  compound_id bigint NOT NULL REFERENCES compound(id),
  taxon_id bigint NOT NULL REFERENCES taxon(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  measurement text NOT NULL CHECK(measurement IN ('relative_abundance','absolute_abundance','growth','viability','unknown'))
);
COMMENT ON TABLE compound_microbe IS '成分菌变化';

-- 成分微生物基因调控
CREATE TABLE compound_gene (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  compound_id bigint NOT NULL REFERENCES compound(id),
  gene_id bigint NOT NULL REFERENCES microbial_gene(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  level text NOT NULL CHECK(level IN ('dna_abundance','rna_expression','unknown'))
);
COMMENT ON TABLE compound_gene IS '成分微生物基因调控';

-- 成分微生物酶调控
CREATE TABLE compound_protein (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  compound_id bigint NOT NULL REFERENCES compound(id),
  protein_id bigint NOT NULL REFERENCES protein(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  level text NOT NULL CHECK(level IN ('protein_abundance','enzyme_activity','unknown'))
);
COMMENT ON TABLE compound_protein IS '成分微生物酶调控';

-- 交叉喂养
CREATE TABLE cross_feeding (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  donor_id bigint NOT NULL REFERENCES taxon(id),
  recipient_id bigint NOT NULL REFERENCES taxon(id),
  compound_id bigint NOT NULL REFERENCES compound(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  CHECK(donor_id<>recipient_id)
);
COMMENT ON TABLE cross_feeding IS '交叉喂养';

-- 干预疾病结局
CREATE TABLE compound_disease (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  compound_id bigint NOT NULL REFERENCES compound(id),
  disease_id bigint NOT NULL REFERENCES disease(id),
  observation_id bigint NOT NULL REFERENCES observation(id),
  relation text NOT NULL CHECK(relation IN ('improved','worsened','unchanged','associated'))
);
COMMENT ON TABLE compound_disease IS '干预疾病结局';

-- 基因簇不得跨基因组。宿主基因产物不得跨物种。
CREATE FUNCTION validate_cluster_member() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (SELECT genome_id FROM gene_cluster WHERE id=NEW.cluster_id)
    IS DISTINCT FROM (SELECT genome_id FROM microbial_gene WHERE id=NEW.gene_id) THEN
  RAISE EXCEPTION 'cluster and gene must share genome';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER cluster_member_guard BEFORE INSERT OR UPDATE ON cluster_member
FOR EACH ROW EXECUTE FUNCTION validate_cluster_member();
CREATE FUNCTION validate_host_product() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (SELECT host_taxid FROM host_gene WHERE id=NEW.gene_id)
    IS DISTINCT FROM (SELECT host_taxid FROM host_target WHERE id=NEW.target_id) THEN
  RAISE EXCEPTION 'host gene and target must share species';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER host_product_guard BEFORE INSERT OR UPDATE ON host_gene_product
FOR EACH ROW EXECUTE FUNCTION validate_host_product();
-- 防止修改父表绕过成员约束；应新建版本记录。
CREATE FUNCTION immutable_scope() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF to_jsonb(OLD)->TG_ARGV[0] IS DISTINCT FROM to_jsonb(NEW)->TG_ARGV[0] THEN
  RAISE EXCEPTION 'scope immutable: create a new version instead';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER gene_cluster_scope BEFORE UPDATE ON gene_cluster FOR EACH ROW EXECUTE FUNCTION immutable_scope('genome_id');
CREATE TRIGGER microbial_gene_scope BEFORE UPDATE ON microbial_gene FOR EACH ROW EXECUTE FUNCTION immutable_scope('genome_id');
CREATE TRIGGER host_gene_scope BEFORE UPDATE ON host_gene FOR EACH ROW EXECUTE FUNCTION immutable_scope('host_taxid');
CREATE TRIGGER host_target_scope BEFORE UPDATE ON host_target FOR EACH ROW EXECUTE FUNCTION immutable_scope('host_taxid');
CREATE INDEX ON taxon(parent_id);
CREATE INDEX ON strain(taxon_id);
CREATE INDEX ON genome(strain_id);
CREATE INDEX ON microbial_gene(genome_id);
CREATE INDEX ON gene_cluster(genome_id);
CREATE INDEX ON cluster_member(cluster_id);
CREATE INDEX ON cluster_member(gene_id);
CREATE INDEX ON protein(strain_id);
CREATE INDEX ON host_gene_product(gene_id);
CREATE INDEX ON host_gene_product(target_id);
CREATE INDEX ON experiment(source_id);
CREATE INDEX ON experiment(disease_id);
CREATE INDEX ON study_arm(experiment_id);
CREATE INDEX ON exposure(arm_id);
CREATE INDEX ON exposure(compound_id);
CREATE INDEX ON context(experiment_id);
CREATE INDEX ON observation(experiment_id);
CREATE INDEX ON reaction_participant(reaction_id);
CREATE INDEX ON reaction_participant(compound_id);
CREATE INDEX ON transformation(reaction_id);
CREATE INDEX ON transformation(observation_id);
CREATE INDEX ON transformation_actor(transformation_id);
CREATE INDEX ON transformation_actor(taxon_id);
CREATE INDEX ON transformation_actor(strain_id);
CREATE INDEX ON transformation_actor(protein_id);
CREATE INDEX ON herb_compound(herb_id);
CREATE INDEX ON herb_compound(compound_id);
CREATE INDEX ON herb_compound(observation_id);
CREATE INDEX ON gene_product(gene_id);
CREATE INDEX ON gene_product(protein_id);
CREATE INDEX ON gene_product(observation_id);
CREATE INDEX ON gene_annotation(gene_id);
CREATE INDEX ON gene_annotation(term_id);
CREATE INDEX ON gene_annotation(observation_id);
CREATE INDEX ON protein_annotation(protein_id);
CREATE INDEX ON protein_annotation(term_id);
CREATE INDEX ON protein_annotation(observation_id);
CREATE INDEX ON protein_reaction(protein_id);
CREATE INDEX ON protein_reaction(reaction_id);
CREATE INDEX ON protein_reaction(observation_id);
CREATE INDEX ON compound_target(compound_id);
CREATE INDEX ON compound_target(target_id);
CREATE INDEX ON compound_target(observation_id);
CREATE INDEX ON compound_host_gene(compound_id);
CREATE INDEX ON compound_host_gene(gene_id);
CREATE INDEX ON compound_host_gene(observation_id);
CREATE INDEX ON target_disease(target_id);
CREATE INDEX ON target_disease(disease_id);
CREATE INDEX ON target_disease(observation_id);
CREATE INDEX ON microbe_disease(taxon_id);
CREATE INDEX ON microbe_disease(disease_id);
CREATE INDEX ON microbe_disease(observation_id);
CREATE INDEX ON compound_microbe(compound_id);
CREATE INDEX ON compound_microbe(taxon_id);
CREATE INDEX ON compound_microbe(observation_id);
CREATE INDEX ON compound_gene(compound_id);
CREATE INDEX ON compound_gene(gene_id);
CREATE INDEX ON compound_gene(observation_id);
CREATE INDEX ON compound_protein(compound_id);
CREATE INDEX ON compound_protein(protein_id);
CREATE INDEX ON compound_protein(observation_id);
CREATE INDEX ON cross_feeding(donor_id);
CREATE INDEX ON cross_feeding(recipient_id);
CREATE INDEX ON cross_feeding(compound_id);
CREATE INDEX ON cross_feeding(observation_id);
CREATE INDEX ON compound_disease(compound_id);
CREATE INDEX ON compound_disease(disease_id);
CREATE INDEX ON compound_disease(observation_id);
COMMIT;
