-- 仅虚构教学数据；全部回滚。不使用真实PMID/菌名制造科研事实。
-- psql -v ON_ERROR_STOP=1 -d your_database -f acceptance.sql
BEGIN;
SET LOCAL search_path TO tcm_er_v2, public;
DO $$
DECLARE
 src bigint; e1 bigint; e2 bigint; arm2 bigint; o1 bigint; o2 bigint;
 a bigint; b bigint; c bigint; r bigint; x bigint; tx bigint;
 s bigint; g1 bigint; g2 bigint; gene1 bigint; gene2 bigint; cl bigint;
 hg bigint; ht bigint; ht2 bigint; caught boolean;
BEGIN
 INSERT INTO source_record(kind,locator,version,title)
 VALUES('synthetic','ER-V2-ACCEPTANCE','1','虚构验收案例') RETURNING id INTO src;
 INSERT INTO experiment(source_id,local_key,system) VALUES(src,'culture-1','culture') RETURNING id INTO e1;
 INSERT INTO experiment(source_id,local_key,system) VALUES(src,'culture-2','culture') RETURNING id INTO e2;
 INSERT INTO study_arm(experiment_id,name,is_control) VALUES(e2,'foreign-arm',false) RETURNING id INTO arm2;
 INSERT INTO observation(experiment_id,endpoint,metric,direction,evidence_method,quote,location,extraction_version)
 VALUES(e1,'转化产物','presence','detected','synthetic LC-MS','虚构A转化为B和C','synthetic figure','manual-v1') RETURNING id INTO o1;
 INSERT INTO observation(experiment_id,endpoint,metric,direction,evidence_method,quote,location,extraction_version)
 VALUES(e1,'转化产物','presence','not_detected','synthetic LC-MS','虚构另一条件未检出产物','synthetic figure 2','manual-v1') RETURNING id INTO o2;
 INSERT INTO compound(name,identity_status) VALUES('SYNTHETIC-A','unresolved') RETURNING id INTO a;
 INSERT INTO compound(name,identity_status) VALUES('SYNTHETIC-B','unresolved') RETURNING id INTO b;
 INSERT INTO compound(name,identity_status) VALUES('SYNTHETIC-C','unresolved') RETURNING id INTO c;
 INSERT INTO reaction(name,direction,completeness) VALUES('虚构多产物反应','forward','partial') RETURNING id INTO r;
 INSERT INTO reaction_participant(reaction_id,compound_id,side) VALUES(r,a,'substrate'),(r,b,'product'),(r,c,'product');
 INSERT INTO transformation(reaction_id,observation_id,substrate_origin,product_origin,attribution)
 VALUES(r,o1,'drug','unknown','community') RETURNING id INTO x;
 INSERT INTO transformation(reaction_id,observation_id,substrate_origin,product_origin,attribution)
 VALUES(r,o2,'drug','unknown','community');
 IF (SELECT count(*) FROM reaction_participant WHERE reaction_id=r AND side='product')<>2 THEN
  RAISE EXCEPTION 'multiple products lost';
 END IF;
 IF EXISTS(SELECT 1 FROM transformation_actor WHERE transformation_id=x) THEN
  RAISE EXCEPTION 'unknown catalyst must not invent actor';
 END IF;
 -- 反向/负结果不能覆盖正结果。
 IF (SELECT count(*) FROM transformation WHERE reaction_id=r)<>2 THEN RAISE EXCEPTION 'evidence lost'; END IF;
 -- actor必须恰选一个实体
 caught:=false;
 BEGIN
  INSERT INTO transformation_actor(transformation_id,role) VALUES(x,'tested');
 EXCEPTION WHEN check_violation THEN caught:=true;
 END;
 IF NOT caught THEN RAISE EXCEPTION 'empty actor accepted'; END IF;
 -- 跨实验引用处理组必须失败
 caught:=false;
 BEGIN
  INSERT INTO observation(experiment_id,subject_arm_id,endpoint,metric,direction,evidence_method,quote,location,extraction_version)
  VALUES(e1,arm2,'bad','bad','unknown','synthetic','bad','bad','v1');
 EXCEPTION WHEN foreign_key_violation THEN caught:=true;
 END;
 IF NOT caught THEN RAISE EXCEPTION 'foreign arm accepted'; END IF;
 -- p值超过范围必须失败
 caught:=false;
 BEGIN
  UPDATE observation SET p_value=1.1 WHERE id=o1;
 EXCEPTION WHEN check_violation THEN caught:=true;
 END;
 IF NOT caught THEN RAISE EXCEPTION 'invalid p accepted'; END IF;
 INSERT INTO taxon(name,rank) VALUES('SYNTHETIC-TAXON','species') RETURNING id INTO tx;
 INSERT INTO strain(taxon_id,name) VALUES(tx,'synthetic strain') RETURNING id INTO s;
 INSERT INTO genome(strain_id,assembly_version) VALUES(s,'SYNTHETIC-ASSEMBLY-1.1') RETURNING id INTO g1;
 INSERT INTO genome(strain_id,assembly_version) VALUES(s,'SYNTHETIC-ASSEMBLY-2.1') RETURNING id INTO g2;
 INSERT INTO microbial_gene(genome_id,locus_tag) VALUES(g1,'syn_locus') RETURNING id INTO gene1;
 INSERT INTO microbial_gene(genome_id,locus_tag) VALUES(g2,'syn_locus') RETURNING id INTO gene2;
 INSERT INTO gene_cluster(genome_id,name) VALUES(g1,'synthetic cluster') RETURNING id INTO cl;
 INSERT INTO cluster_member(cluster_id,gene_id) VALUES(cl,gene1);
 caught:=false;
 BEGIN
  INSERT INTO cluster_member(cluster_id,gene_id) VALUES(cl,gene2);
 EXCEPTION WHEN raise_exception THEN caught:=true;
 END;
 IF NOT caught THEN RAISE EXCEPTION 'cross-genome member accepted'; END IF;
 -- 更新父表不得绕开所属范围限制
 caught:=false;
 BEGIN
  UPDATE microbial_gene SET genome_id=g2 WHERE id=gene1;
 EXCEPTION WHEN raise_exception THEN caught:=true;
 END;
 IF NOT caught THEN RAISE EXCEPTION 'parent update bypass accepted'; END IF;
 INSERT INTO host_gene(host_taxid,symbol,gene_accession) VALUES(9606,'SYNTHETIC-G','SYN-G') RETURNING id INTO hg;
 INSERT INTO host_target(host_taxid,name,kind,accession) VALUES(9606,'SYNTHETIC-P','protein','SYN-P') RETURNING id INTO ht;
 INSERT INTO host_target(host_taxid,name,kind,accession) VALUES(10090,'SYNTHETIC-P','protein','SYN-P') RETURNING id INTO ht2;
 INSERT INTO host_gene_product(gene_id,target_id) VALUES(hg,ht);
 caught:=false;
 BEGIN
  INSERT INTO host_gene_product(gene_id,target_id) VALUES(hg,ht2);
 EXCEPTION WHEN raise_exception THEN caught:=true;
 END;
 IF NOT caught THEN RAISE EXCEPTION 'cross-species product accepted'; END IF;
 RAISE NOTICE 'All synthetic acceptance checks passed; changes will be rolled back.';
END $$;
ROLLBACK;
