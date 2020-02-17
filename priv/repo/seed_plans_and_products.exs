alias Sanbase.Repo

Repo.query!("""
INSERT INTO products (id, name) VALUES
  (1, 'SanAPI by Santiment'),
  (2, 'Sanbase by Santiment'),
  (3, 'Sheets by Santiment'),
  (4, 'Sandata by Santiment'),
  (5, 'Exchange Wallets by Santiment')
  ON CONFLICT DO NOTHING
""")

Repo.query!("""
INSERT INTO plans (id, name, product_id, amount, currency, interval) VALUES
  (1, 'FREE', 1, 0, 'USD', 'month'),
  (2, 'ESSENTIAL', 1, 11900, 'USD', 'month'),
  (3, 'PRO', 1, 35900, 'USD', 'month'),
  (4, 'PREMIUM', 1, 71900, 'USD', 'month'),
  (5, 'CUSTOM', 1, 0, 'USD', 'month'),
  (6, 'ESSENTIAL', 1, 128520, 'USD', 'year'),
  (7, 'PRO', 1, 387720, 'USD', 'year'),
  (8, 'PREMIUM', 1, 776520, 'USD', 'year'),
  (9, 'CUSTOM', 1, 0, 'USD', 'year'),
  (11, 'FREE', 2, 0, 'USD', 'month'),
  (12, 'BASIC', 2, 1100, 'USD', 'month'),
  (13, 'PRO', 2, 5100, 'USD', 'month'),
  (14, 'ENTERPRISE', 2, 0, 'USD', 'month'),
  (15, 'BASIC', 2, 10800, 'USD', 'year'),
  (16, 'PRO', 2, 54000, 'USD', 'year'),
  (17, 'ENTERPRISE', 2, 0, 'USD', 'year'),
  (21, 'FREE', 3, 0, 'USD', 'month'),
  (22, 'BASIC', 3, 8900, 'USD', 'month'),
  (23, 'PRO', 3, 18900, 'USD', 'month'),
  (24, 'ENTERPRISE', 3, 0, 'USD', 'month'),
  (25, 'BASIC', 3, 96120, 'USD', 'year'),
  (26, 'PRO', 3, 204120, 'USD', 'year'),
  (27, 'ENTERPRISE', 3, 0, 'USD', 'year'),
  (41, 'BASIC', 4, 5000, 'USD', 'month'),
  (42, 'PRO', 4, 14000, 'USD', 'month'),
  (43, 'PREMIUM', 4, 29000, 'USD', 'month'),
  (44, 'BASIC', 4, 54000, 'USD', 'year'),
  (45, 'PRO', 4, 151200, 'USD', 'year'),
  (46, 'PREMIUM', 4, 313200, 'USD', 'year'),
  (51, 'EXTENSION', 5, 20000, 'USD', 'month'),
  (52, 'EXTENSION', 5, 216000, 'USD', 'year'),
  (101, 'ESSENTIAL', 1, 16000, 'USD', 'month'),
  (102, 'PRO', 1, 42000, 'USD', 'month'),
  (103, 'ESSENTIAL', 1, 178800, 'USD', 'year'),
  (104, 'PRO', 1, 478800, 'USD', 'year')
  ON CONFLICT DO NOTHING
""")
