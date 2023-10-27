Sanbase.Repo.query!("""
INSERT INTO products (id, name, code) VALUES
  (1, 'Neuro by Santiment', 'SANAPI'),
  (2, 'Sanbase by Santiment', 'SANBASE'),
  (4, 'Sandata by Santiment', 'SANDATA'),
  (5, 'Exchange Wallets by Santiment', 'SAN_EXCHANGE_WALLETS')
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
  (4,'PREMIUM',1,71900,'USD','month',4),
  (6,'ESSENTIAL',1,128520,'USD','year',3),
  (7,'PRO',1,387720,'USD','year',2),
  (8,'PREMIUM',1,776520,'USD','year',1),
  (11,'FREE',2,0,'USD','month',9),
  (205,'BASIC',2,2500,'USD','month',9),
  (201,'PRO',2,4900,'USD','month',8),
  (203,'PRO_PLUS',2,24900,'USD','month',7),
  (202,'PRO',2,52900,'USD','year',6),
  (204,'PRO_PLUS',2,270000,'USD','year',5),
  (41,'BASIC',4,5000,'USD','month',0),
  (42,'PRO',4,14000,'USD','month',0),
  (43,'PREMIUM',4,29000,'USD','month',0),
  (44,'BASIC',4,54000,'USD','year',0),
  (45,'PRO',4,151200,'USD','year',0),
  (46,'PREMIUM',4,313200,'USD','year',0),
  (51,'EXTENSION',5,20000,'USD','month',0),
  (52,'EXTENSION',5,216000,'USD','year',0)
  ON CONFLICT DO NOTHING
""")
