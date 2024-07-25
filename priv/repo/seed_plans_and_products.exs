Sanbase.Repo.query!("""
INSERT INTO products (id, name, code) VALUES
  (1, 'Sanapi by Santiment', 'SANAPI'),
  (2, 'Sanbase by Santiment', 'SANBASE')
  ON CONFLICT DO NOTHING
""")

Sanbase.Repo.query!("""
INSERT INTO plans (id, name, product_id, amount, currency, interval, "order") VALUES
  (1,'FREE',1,0,'USD','month',13),
  (101,'ESSENTIAL',1,16000,'USD','month',12),
  (102,'PRO',1,42000,'USD','month',11),
  (5,'CUSTOM',1,0,'USD','month',10),
  (103,'ESSENTIAL',1,178800,'USD','year',9),
  (104,'PRO',1,478800,'USD','year',8),
  (9,'CUSTOM',1,0,'USD','year',7),
  (2,'ESSENTIAL',1,11900,'USD','month',6),
  (3,'PRO',1,35900,'USD','month',5),
  (6,'ESSENTIAL',1,128520,'USD','year',3),
  (7,'PRO',1,387720,'USD','year',2),
  (11,'FREE',2,0,'USD','month',9),
  (205,'BASIC',2,2500,'USD','month',9),
  (201,'PRO',2,4900,'USD','month',8),
  (203,'PRO_PLUS',2,24900,'USD','month',7),
  (202,'PRO',2,52900,'USD','year',6),
  (204,'PRO_PLUS',2,270000,'USD','year',5),
  (206,'PRO',2,1500,'USD','month',0),
  (207,'PRO',2,15900,'USD','year',0),
  (208,'PRO_PLUS',2,7500,'USD','month',0),
  (209,'PRO_PLUS',2,81000,'USD','year',0),
  (210,'MAX',2,24900,'USD','month',0),
  (211,'MAX',2,270000,'USD','year',0),
  (107,'BUSINESS_PRO',1,42000,'USD','month',20),
  (108,'BUSINESS_PRO',1,478800,'USD','year',21),
  (109,'BUSINESS_MAX',1,99900,'USD','month',22),
  (110,'BUSINESS_MAX',1,1138800,'USD','year',23)
  ON CONFLICT DO NOTHING
""")

# Otherwise when we try to create a custom plan it will fail
# as plans_id_seq will produce `1` as the next value
Sanbase.Repo.query!("""
ALTER SEQUENCE plans_id_seq RESTART WITH 1000;
""")
