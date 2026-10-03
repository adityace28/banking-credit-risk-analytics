-- =====================================================================
-- RETAIL BANKING CREDIT RISK & CHURN ANALYTICS
-- File    : schema_and_data.sql
-- Purpose : Creates 4 relational tables and loads synthetic data
-- Target  : PostgreSQL 12+ (tested logic for pgAdmin 4)
-- Note    : All dates are relative to CURRENT_TIMESTAMP, so the dormancy
--           and churn scenarios stay valid whenever you run the script.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. CLEAN RESET (safe to re-run; CASCADE also drops dependent views)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS loan_history CASCADE;
DROP TABLE IF EXISTS transactions CASCADE;
DROP TABLE IF EXISTS accounts CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

-- ---------------------------------------------------------------------
-- 1. TABLE: customers
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id        SERIAL PRIMARY KEY,
    full_name          VARCHAR(100)  NOT NULL,
    age                INT           NOT NULL CHECK (age BETWEEN 18 AND 100),
    income             NUMERIC(14,2) NOT NULL CHECK (income >= 0),
    cibil_score        INT           NOT NULL CHECK (cibil_score BETWEEN 300 AND 900),
    employment_status  VARCHAR(20)   NOT NULL DEFAULT 'Salaried'
        CHECK (employment_status IN ('Salaried', 'Self-Employed', 'Unemployed', 'Retired', 'Student')),
    join_date          DATE          NOT NULL DEFAULT CURRENT_DATE
);

-- ---------------------------------------------------------------------
-- 2. TABLE: accounts
-- ---------------------------------------------------------------------
CREATE TABLE accounts (
    account_id      SERIAL PRIMARY KEY,
    customer_id     INT           NOT NULL REFERENCES customers (customer_id) ON DELETE CASCADE,
    account_type    VARCHAR(10)   NOT NULL CHECK (account_type IN ('Savings', 'Current')),
    balance         NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    account_status  VARCHAR(10)   NOT NULL DEFAULT 'Active'
        CHECK (account_status IN ('Active', 'Dormant', 'Frozen', 'Closed')),
    created_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 3. TABLE: transactions
-- ---------------------------------------------------------------------
CREATE TABLE transactions (
    transaction_id    SERIAL PRIMARY KEY,
    account_id        INT           NOT NULL REFERENCES accounts (account_id) ON DELETE CASCADE,
    transaction_date  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    amount            NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    transaction_type  VARCHAR(12)   NOT NULL CHECK (transaction_type IN ('Deposit', 'Withdrawal', 'Transfer')),
    merchant_category VARCHAR(50)   NOT NULL DEFAULT 'Other'
);

-- ---------------------------------------------------------------------
-- 4. TABLE: loan_history
-- ---------------------------------------------------------------------
CREATE TABLE loan_history (
    loan_id                SERIAL PRIMARY KEY,
    customer_id            INT           NOT NULL REFERENCES customers (customer_id) ON DELETE CASCADE,
    principal_amount       NUMERIC(14,2) NOT NULL CHECK (principal_amount > 0),
    interest_rate          NUMERIC(5,2)  NOT NULL CHECK (interest_rate > 0 AND interest_rate <= 40),
    term_months            INT           NOT NULL CHECK (term_months > 0),
    missed_payments_count  INT           NOT NULL DEFAULT 0 CHECK (missed_payments_count >= 0),
    loan_status            VARCHAR(10)   NOT NULL DEFAULT 'Active'
        CHECK (loan_status IN ('Active', 'Defaulted', 'Closed'))
);

-- ---------------------------------------------------------------------
-- 5. INDEXES (speed up joins and window-function scans)
-- ---------------------------------------------------------------------
CREATE INDEX idx_accounts_customer_id      ON accounts (customer_id);
CREATE INDEX idx_transactions_account_date ON transactions (account_id, transaction_date);
CREATE INDEX idx_loan_history_customer_id  ON loan_history (customer_id);

-- ---------------------------------------------------------------------
-- 6. DATA: customers (15 rows)
--    Edge cases: low CIBIL, unemployed, retired, student, very high income
-- ---------------------------------------------------------------------
INSERT INTO customers (full_name, age, income, cibil_score, employment_status, join_date) VALUES
('Aarav Sharma',    34, 1200000.00, 785, 'Salaried',      CURRENT_DATE - 1500),
('Priya Nair',      29,  950000.00, 742, 'Salaried',      CURRENT_DATE - 1200),
('Rohan Mehta',     45, 2400000.00, 801, 'Self-Employed', CURRENT_DATE - 2400),
('Sneha Kulkarni',  38,  700000.00, 668, 'Salaried',      CURRENT_DATE - 1800),
('Vikram Singh',    52,  450000.00, 540, 'Self-Employed', CURRENT_DATE - 2100),
('Anjali Desai',    27,  380000.00, 612, 'Salaried',      CURRENT_DATE - 900),
('Karan Malhotra',  41, 1800000.00, 720, 'Self-Employed', CURRENT_DATE - 2000),
('Meera Iyer',      33,  600000.00, 590, 'Unemployed',    CURRENT_DATE - 1300),
('Suresh Patil',    58,  300000.00, 505, 'Retired',       CURRENT_DATE - 3000),
('Divya Reddy',     31, 1500000.00, 760, 'Salaried',      CURRENT_DATE - 1100),
('Arjun Verma',     24,  250000.00, 580, 'Student',       CURRENT_DATE - 450),
('Neha Gupta',      36, 1100000.00, 710, 'Salaried',      CURRENT_DATE - 1600),
('Rahul Joshi',     47,  520000.00, 560, 'Self-Employed', CURRENT_DATE - 2200),
('Pooja Bansal',    30,  850000.00, 695, 'Salaried',      CURRENT_DATE - 1000),
('Manoj Kumar',     49, 3200000.00, 820, 'Self-Employed', CURRENT_DATE - 2800);

-- ---------------------------------------------------------------------
-- 7. DATA: accounts (20 rows)
--    Edge cases: dormant high balances, a frozen account, an account
--    with a large balance and zero transactions (account_id 19)
-- ---------------------------------------------------------------------
INSERT INTO accounts (customer_id, account_type, balance, account_status, created_at) VALUES
(1,  'Savings',  450000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '1450 days'),
(1,  'Current',  120000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '900 days'),
(2,  'Savings',  280000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '1150 days'),
(3,  'Current', 1250000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '2300 days'),
(3,  'Savings',  640000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '2200 days'),
(4,  'Savings',   85000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '1700 days'),
(5,  'Savings',    4200.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '2000 days'),
(6,  'Savings',   15000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '850 days'),
(7,  'Current',  980000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '1900 days'),
(8,  'Savings',    2300.00, 'Dormant', CURRENT_TIMESTAMP - INTERVAL '1250 days'),
(9,  'Savings',   76000.00, 'Dormant', CURRENT_TIMESTAMP - INTERVAL '2900 days'),
(10, 'Savings',  520000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '1050 days'),
(11, 'Savings',     800.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '420 days'),
(12, 'Savings',  190000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '1550 days'),
(13, 'Current',   31000.00, 'Frozen',  CURRENT_TIMESTAMP - INTERVAL '2100 days'),
(14, 'Savings',   95000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '950 days'),
(15, 'Current', 2800000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '2700 days'),
(15, 'Savings', 1500000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '2600 days'),
(7,  'Savings',  210000.00, 'Active',  CURRENT_TIMESTAMP - INTERVAL '1000 days'),
(12, 'Current',   67000.00, 'Dormant', CURRENT_TIMESTAMP - INTERVAL '1400 days');

-- ---------------------------------------------------------------------
-- 8. DATA: transactions (66 rows)
--    Edge cases:
--      * account 6  : heavy activity 4-6 months ago, near-silence since (churn drop-off)
--      * accounts 5, 11, 16, 18, 20 : last activity more than 90 days ago (dormant)
--      * account 19 : zero transactions ever
--      * account 4, 9, 17 : large business inflows and investment transfers
-- ---------------------------------------------------------------------
INSERT INTO transactions (account_id, transaction_date, amount, transaction_type, merchant_category) VALUES
(1,  CURRENT_TIMESTAMP - INTERVAL '5 days',   4500.00,    'Withdrawal', 'Groceries'),
(1,  CURRENT_TIMESTAMP - INTERVAL '12 days',  12000.00,   'Withdrawal', 'Travel'),
(1,  CURRENT_TIMESTAMP - INTERVAL '20 days',  100000.00,  'Deposit',    'Salary'),
(1,  CURRENT_TIMESTAMP - INTERVAL '35 days',  8000.00,    'Withdrawal', 'Dining'),
(1,  CURRENT_TIMESTAMP - INTERVAL '50 days',  100000.00,  'Deposit',    'Salary'),
(1,  CURRENT_TIMESTAMP - INTERVAL '70 days',  15000.00,   'Withdrawal', 'Electronics'),
(1,  CURRENT_TIMESTAMP - INTERVAL '95 days',  100000.00,  'Deposit',    'Salary'),
(1,  CURRENT_TIMESTAMP - INTERVAL '130 days', 6000.00,    'Withdrawal', 'Utilities'),
(1,  CURRENT_TIMESTAMP - INTERVAL '160 days', 100000.00,  'Deposit',    'Salary'),
(1,  CURRENT_TIMESTAMP - INTERVAL '200 days', 9500.00,    'Withdrawal', 'Groceries'),
(2,  CURRENT_TIMESTAMP - INTERVAL '15 days',  25000.00,   'Transfer',   'Business'),
(2,  CURRENT_TIMESTAMP - INTERVAL '45 days',  30000.00,   'Transfer',   'Business'),
(2,  CURRENT_TIMESTAMP - INTERVAL '110 days', 60000.00,   'Deposit',    'Business'),
(3,  CURRENT_TIMESTAMP - INTERVAL '3 days',   3200.00,    'Withdrawal', 'Dining'),
(3,  CURRENT_TIMESTAMP - INTERVAL '18 days',  79000.00,   'Deposit',    'Salary'),
(3,  CURRENT_TIMESTAMP - INTERVAL '33 days',  5400.00,    'Withdrawal', 'Groceries'),
(3,  CURRENT_TIMESTAMP - INTERVAL '48 days',  79000.00,   'Deposit',    'Salary'),
(3,  CURRENT_TIMESTAMP - INTERVAL '80 days',  22000.00,   'Withdrawal', 'Travel'),
(3,  CURRENT_TIMESTAMP - INTERVAL '140 days', 79000.00,   'Deposit',    'Salary'),
(4,  CURRENT_TIMESTAMP - INTERVAL '2 days',   150000.00,  'Transfer',   'Investment'),
(4,  CURRENT_TIMESTAMP - INTERVAL '25 days',  400000.00,  'Deposit',    'Business'),
(4,  CURRENT_TIMESTAMP - INTERVAL '60 days',  200000.00,  'Transfer',   'Investment'),
(4,  CURRENT_TIMESTAMP - INTERVAL '100 days', 350000.00,  'Deposit',    'Business'),
(4,  CURRENT_TIMESTAMP - INTERVAL '150 days', 80000.00,   'Withdrawal', 'Insurance'),
(5,  CURRENT_TIMESTAMP - INTERVAL '200 days', 300000.00,  'Deposit',    'Investment'),
(5,  CURRENT_TIMESTAMP - INTERVAL '260 days', 340000.00,  'Deposit',    'Investment'),
(6,  CURRENT_TIMESTAMP - INTERVAL '40 days',  1500.00,    'Withdrawal', 'Fuel'),
(6,  CURRENT_TIMESTAMP - INTERVAL '120 days', 7000.00,    'Withdrawal', 'Groceries'),
(6,  CURRENT_TIMESTAMP - INTERVAL '135 days', 6500.00,    'Withdrawal', 'Dining'),
(6,  CURRENT_TIMESTAMP - INTERVAL '150 days', 9000.00,    'Withdrawal', 'Utilities'),
(6,  CURRENT_TIMESTAMP - INTERVAL '165 days', 58000.00,   'Deposit',    'Salary'),
(6,  CURRENT_TIMESTAMP - INTERVAL '180 days', 4000.00,    'Withdrawal', 'Fuel'),
(6,  CURRENT_TIMESTAMP - INTERVAL '210 days', 5500.00,    'Withdrawal', 'Groceries'),
(7,  CURRENT_TIMESTAMP - INTERVAL '8 days',   2000.00,    'Withdrawal', 'Cash'),
(7,  CURRENT_TIMESTAMP - INTERVAL '55 days',  1800.00,    'Withdrawal', 'Cash'),
(7,  CURRENT_TIMESTAMP - INTERVAL '190 days', 6000.00,    'Deposit',    'Business'),
(8,  CURRENT_TIMESTAMP - INTERVAL '6 days',   1200.00,    'Withdrawal', 'Dining'),
(8,  CURRENT_TIMESTAMP - INTERVAL '28 days',  28000.00,   'Deposit',    'Salary'),
(8,  CURRENT_TIMESTAMP - INTERVAL '57 days',  900.00,     'Withdrawal', 'Entertainment'),
(8,  CURRENT_TIMESTAMP - INTERVAL '90 days',  28000.00,   'Deposit',    'Salary'),
(9,  CURRENT_TIMESTAMP - INTERVAL '4 days',   250000.00,  'Deposit',    'Business'),
(9,  CURRENT_TIMESTAMP - INTERVAL '22 days',  120000.00,  'Transfer',   'Business'),
(9,  CURRENT_TIMESTAMP - INTERVAL '52 days',  300000.00,  'Deposit',    'Business'),
(9,  CURRENT_TIMESTAMP - INTERVAL '85 days',  45000.00,   'Withdrawal', 'Travel'),
(9,  CURRENT_TIMESTAMP - INTERVAL '125 days', 90000.00,   'Transfer',   'Business'),
(10, CURRENT_TIMESTAMP - INTERVAL '240 days', 3000.00,    'Withdrawal', 'Groceries'),
(11, CURRENT_TIMESTAMP - INTERVAL '220 days', 25000.00,   'Deposit',    'Pension'),
(11, CURRENT_TIMESTAMP - INTERVAL '300 days', 5000.00,    'Withdrawal', 'Healthcare'),
(12, CURRENT_TIMESTAMP - INTERVAL '7 days',   125000.00,  'Deposit',    'Salary'),
(12, CURRENT_TIMESTAMP - INTERVAL '14 days',  18000.00,   'Withdrawal', 'Travel'),
(12, CURRENT_TIMESTAMP - INTERVAL '37 days',  125000.00,  'Deposit',    'Salary'),
(12, CURRENT_TIMESTAMP - INTERVAL '67 days',  32000.00,   'Withdrawal', 'Electronics'),
(12, CURRENT_TIMESTAMP - INTERVAL '97 days',  125000.00,  'Deposit',    'Salary'),
(13, CURRENT_TIMESTAMP - INTERVAL '10 days',  400.00,     'Withdrawal', 'Entertainment'),
(13, CURRENT_TIMESTAMP - INTERVAL '41 days',  650.00,     'Withdrawal', 'Dining'),
(14, CURRENT_TIMESTAMP - INTERVAL '9 days',   11000.00,   'Withdrawal', 'Healthcare'),
(14, CURRENT_TIMESTAMP - INTERVAL '39 days',  92000.00,   'Deposit',    'Salary'),
(14, CURRENT_TIMESTAMP - INTERVAL '150 days', 14000.00,   'Withdrawal', 'Education'),
(15, CURRENT_TIMESTAMP - INTERVAL '170 days', 12000.00,   'Withdrawal', 'Cash'),
(16, CURRENT_TIMESTAMP - INTERVAL '130 days', 18000.00,   'Withdrawal', 'Dining'),
(16, CURRENT_TIMESTAMP - INTERVAL '175 days', 70000.00,   'Deposit',    'Salary'),
(17, CURRENT_TIMESTAMP - INTERVAL '1 days',   500000.00,  'Transfer',   'Investment'),
(17, CURRENT_TIMESTAMP - INTERVAL '30 days',  900000.00,  'Deposit',    'Business'),
(17, CURRENT_TIMESTAMP - INTERVAL '75 days',  120000.00,  'Withdrawal', 'Travel'),
(18, CURRENT_TIMESTAMP - INTERVAL '250 days', 1500000.00, 'Deposit',    'Investment'),
(20, CURRENT_TIMESTAMP - INTERVAL '280 days', 67000.00,   'Deposit',    'Business');

-- ---------------------------------------------------------------------
-- 9. DATA: loan_history (15 rows)
--    Edge cases: defaulted loans with many missed payments, closed loan,
--    large low-risk mortgage-style loans
-- ---------------------------------------------------------------------
INSERT INTO loan_history (customer_id, principal_amount, interest_rate, term_months, missed_payments_count, loan_status) VALUES
(1,  3000000.00,  8.50, 240, 0, 'Active'),
(2,   600000.00, 10.50,  60, 0, 'Active'),
(3,  5000000.00,  9.00, 180, 0, 'Active'),
(4,  1200000.00, 11.00, 120, 2, 'Active'),
(5,   800000.00, 13.50,  60, 6, 'Defaulted'),
(6,   400000.00, 14.00,  36, 3, 'Active'),
(7,  2500000.00,  9.50, 120, 1, 'Active'),
(8,   300000.00, 16.00,  24, 7, 'Defaulted'),
(9,   250000.00, 15.00,  36, 5, 'Defaulted'),
(10, 1000000.00,  9.00,  84, 0, 'Closed'),
(11,  150000.00, 15.50,  24, 4, 'Active'),
(12,  900000.00, 10.00,  72, 0, 'Active'),
(13,  700000.00, 14.50,  48, 4, 'Defaulted'),
(14,  450000.00, 12.00,  48, 1, 'Active'),
(15, 8000000.00,  8.00, 240, 0, 'Active');

-- ---------------------------------------------------------------------
-- 10. SANITY CHECK: row counts per table
-- ---------------------------------------------------------------------
SELECT 'customers'    AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'accounts'     AS table_name, COUNT(*) AS row_count FROM accounts
UNION ALL
SELECT 'transactions' AS table_name, COUNT(*) AS row_count FROM transactions
UNION ALL
SELECT 'loan_history' AS table_name, COUNT(*) AS row_count FROM loan_history;
