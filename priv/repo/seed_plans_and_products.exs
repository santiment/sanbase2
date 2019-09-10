alias Sanbase.Repo

Repo.query!("""
INSERT INTO products (id, name) VALUES
  (1, 'Neuro by Santiment'),
  (2, 'Sanbase by Santiment'),
  (3, 'Sheets by Santiment'),
  (4, 'Graphs by Santiment')
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
  (27, 'ENTERPRISE', 3, 0, 'USD', 'year')
  ON CONFLICT DO NOTHING
""")
