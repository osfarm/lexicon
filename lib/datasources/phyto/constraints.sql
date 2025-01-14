ALTER TABLE phyto.phyto ADD FOREIGN KEY (nature) REFERENCES phyto.type_phyto(code);
ALTER TABLE phyto.phyto ADD FOREIGN KEY (formulation) REFERENCES phyto.formulation(code);
ALTER TABLE phyto.phyto ADD FOREIGN KEY (firm_name) REFERENCES phyto.firme(code);

ALTER TABLE phyto.usage ADD FOREIGN KEY (product_code) REFERENCES phyto.phyto(product_code);
ALTER TABLE phyto.usage ADD FOREIGN KEY (culture) REFERENCES phyto.culture(code);
ALTER TABLE phyto.usage ADD FOREIGN KEY (cible) REFERENCES phyto.cible(code);
ALTER TABLE phyto.usage ADD FOREIGN KEY (dose_unit) REFERENCES phyto.unite_usage(code);
ALTER TABLE phyto.usage ADD FOREIGN KEY (treatment) REFERENCES phyto.traitement(code);

ALTER TABLE phyto.cible ADD FOREIGN KEY (type_cible) REFERENCES phyto.type_cible(code);
ALTER TABLE phyto.clp_phyto ADD FOREIGN KEY (product_code) REFERENCES phyto.phyto(product_code);
ALTER TABLE phyto.clp_phyto ADD FOREIGN KEY (code) REFERENCES phyto.clp(code);
ALTER TABLE phyto.phrase_phyto ADD FOREIGN KEY (product_code) REFERENCES phyto.phyto(product_code);

CREATE INDEX ON phyto.phyto ((lower(product_code)));
CREATE INDEX ON phyto.usage ((lower(product_code)));
CREATE INDEX ON phyto.clp_phyto ((lower(product_code)));