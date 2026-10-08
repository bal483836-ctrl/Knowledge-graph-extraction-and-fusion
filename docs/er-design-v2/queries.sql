-- 这些查询返回候选路径及每跳证据，不返回“机制证实”标签。
SET search_path TO tcm_er_v2, public;
-- 路线②：药源性转化产物 → 宿主靶点 → 疾病。
-- 同实验标志只是出处相同，不能代替整链因果验证。
SELECT sub.name AS substrate, prod.name AS product, ht.name AS target, ds.name AS disease,
 tr.id AS transformation_id, tr.attribution,
 ot.id AS transformation_observation, oc.id AS target_observation, od.id AS disease_observation,
 et.source_id AS transformation_source, ec.source_id AS target_source, ed.source_id AS disease_source,
 et.host_taxid AS transformation_host, ec.host_taxid AS target_experiment_host,
 ht.host_taxid AS target_species,
 rt.relation AS target_disease_relation,
 (et.id=ec.id AND ec.id=ed.id) AS same_experiment,
 CASE WHEN et.id=ec.id AND ec.id=ed.id
      THEN 'same_experiment_candidate' ELSE 'cross_study_candidate' END AS path_status
FROM transformation tr
JOIN reaction_participant rs ON rs.reaction_id=tr.reaction_id AND rs.side='substrate'
JOIN reaction_participant rp ON rp.reaction_id=tr.reaction_id AND rp.side='product'
JOIN compound sub ON sub.id=rs.compound_id
JOIN compound prod ON prod.id=rp.compound_id
JOIN compound_target ct ON ct.compound_id=prod.id
JOIN host_target ht ON ht.id=ct.target_id
JOIN target_disease rt ON rt.target_id=ht.id
JOIN disease ds ON ds.id=rt.disease_id
JOIN observation ot ON ot.id=tr.observation_id
JOIN observation oc ON oc.id=ct.observation_id
JOIN observation od ON od.id=rt.observation_id
JOIN experiment et ON et.id=ot.experiment_id
JOIN experiment ec ON ec.id=oc.experiment_id
JOIN experiment ed ON ed.id=od.experiment_id
WHERE tr.substrate_origin='drug' AND tr.product_origin='drug_derived'
 AND ot.review_status='accepted' AND oc.review_status='accepted' AND od.review_status='accepted';
-- 多底物/产物查询可能返回多组组合；不得把组合数当独立证据数。

-- 功能主线待补：已知蛋白参与的转化，缺少编码基因证据。
SELECT DISTINCT p.id AS protein_id,p.name,tr.id AS transformation_id,tr.observation_id
FROM protein p
JOIN transformation_actor a ON a.protein_id=p.id
JOIN transformation tr ON tr.id=a.transformation_id
WHERE NOT EXISTS(
 SELECT 1 FROM gene_product gp JOIN observation o ON o.id=gp.observation_id
 WHERE gp.protein_id=p.id AND o.review_status='accepted'
);

-- 未知菌/酶转化清单：用于后续完善优先级。
SELECT t.id,t.reaction_id,t.observation_id,t.attribution
FROM transformation t
WHERE NOT EXISTS(SELECT 1 FROM transformation_actor a WHERE a.transformation_id=t.id);
