-- =====================================================================
-- RETAIL BANKING CREDIT RISK & CHURN ANALYTICS
-- File    : analysis_queries.sql
-- Purpose : Six advanced analytical queries
-- Run     : Run schema_and_data.sql first.
-- pgAdmin : Highlight ONE query at a time and press F5. If you run the
--           whole file at once, pgAdmin only displays the LAST result.
-- =====================================================================


-- =====================================================================
-- QUERY 1: 30-DAY ROLLING TRANSACTION VELOCITY (PER CUSTOMER)
-- Business use: spots sudden spending spikes (possible fraud) or
-- slowdowns (possible disengagement).
-- Spend = Withdrawals + Transfers (money leaving the account).
-- Two measures are shown side by side:
--   rolling_30_row_spend : the frame requested, ROWS BETWEEN 30 PRECEDING
--                          AND CURRENT ROW (the current and previous 30
--                          transactions, regardless of how many days
--                          they span)
--   rolling_30_day_spend : a true calendar window, RANGE BETWEEN
--                          INTERVAL '30 days' PRECEDING AND CURRENT ROW
-- =====================================================================
WITH customer_transactions AS (
    SELECT
        a.customer_id,
        t.transaction_id,
        t.transaction_date,
        t.transaction_type,
        t.merchant_category,
        CASE
            WHEN t.transaction_type IN ('Withdrawal', 'Transfer') THEN t.amount
            ELSE 0
        END AS spend_amount
    FROM transactions t
    INNER JOIN accounts a ON a.account_id = t.account_id
)
SELECT
    ct.customer_id,
    c.full_name,
    ct.transaction_date,
    ct.transaction_type,
    ct.merchant_category,
    ct.spend_amount,
    SUM(ct.spend_amount) OVER (
        PARTITION BY ct.customer_id
        ORDER BY ct.transaction_date
        ROWS BETWEEN 30 PRECEDING AND CURRENT ROW
    ) AS rolling_30_row_spend,
    SUM(ct.spend_amount) OVER (
        PARTITION BY ct.customer_id
        ORDER BY ct.transaction_date
        RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW
    ) AS rolling_30_day_spend
FROM customer_transactions ct
INNER JOIN customers c ON c.customer_id = ct.customer_id
ORDER BY ct.customer_id, ct.transaction_date;


-- =====================================================================
-- QUERY 2: CUSTOMER CHURN & DROP-OFF RANKING
-- Business use: finds customers whose activity fell sharply between the
-- last two COMPLETED calendar quarters, then ranks them into quartiles.
-- Method:
--   1. Build a calendar of completed quarters (so quiet quarters count as 0).
--   2. Count transactions per customer per quarter.
--   3. LAG() brings in the previous quarter's count.
--   4. drop_off_pct = (previous - current) / previous * 100.
--   5. NTILE(4) ordered by drop-off (highest first): quartile 1 = highest
--      churn risk, quartile 4 = lowest.
-- Customers with zero transactions in the previous quarter are excluded
-- because a percentage drop cannot be computed from zero.
-- =====================================================================
WITH bounds AS (
    SELECT
        DATE_TRUNC('quarter', MIN(transaction_date))::date AS first_quarter,
        DATE_TRUNC('quarter', MAX(transaction_date))::date AS last_quarter
    FROM transactions
    WHERE transaction_date < DATE_TRUNC('quarter', CURRENT_DATE)
),
quarters AS (
    SELECT GENERATE_SERIES(first_quarter, last_quarter, INTERVAL '3 months')::date AS quarter_start
    FROM bounds
),
customer_quarters AS (
    SELECT c.customer_id, c.full_name, q.quarter_start
    FROM customers c
    CROSS JOIN quarters q
),
quarterly_counts AS (
    SELECT
        a.customer_id,
        DATE_TRUNC('quarter', t.transaction_date)::date AS quarter_start,
        COUNT(*) AS txn_count
    FROM transactions t
    INNER JOIN accounts a ON a.account_id = t.account_id
    WHERE t.transaction_date < DATE_TRUNC('quarter', CURRENT_DATE)
    GROUP BY a.customer_id, DATE_TRUNC('quarter', t.transaction_date)::date
),
filled AS (
    SELECT
        cq.customer_id,
        cq.full_name,
        cq.quarter_start,
        COALESCE(qc.txn_count, 0) AS txn_count
    FROM customer_quarters cq
    LEFT JOIN quarterly_counts qc
        ON qc.customer_id = cq.customer_id
       AND qc.quarter_start = cq.quarter_start
),
lagged AS (
    SELECT
        customer_id,
        full_name,
        quarter_start,
        txn_count,
        LAG(txn_count) OVER (PARTITION BY customer_id ORDER BY quarter_start) AS prev_quarter_txn_count
    FROM filled
),
latest_comparison AS (
    SELECT
        customer_id,
        full_name,
        quarter_start,
        prev_quarter_txn_count,
        txn_count AS current_quarter_txn_count,
        ROUND(100.0 * (prev_quarter_txn_count - txn_count) / prev_quarter_txn_count, 2) AS drop_off_pct
    FROM lagged
    WHERE quarter_start = (SELECT last_quarter FROM bounds)
      AND prev_quarter_txn_count > 0
)
SELECT
    customer_id,
    full_name,
    quarter_start AS latest_completed_quarter,
    prev_quarter_txn_count,
    current_quarter_txn_count,
    drop_off_pct,
    NTILE(4) OVER (ORDER BY drop_off_pct DESC) AS churn_risk_quartile,
    CASE NTILE(4) OVER (ORDER BY drop_off_pct DESC)
        WHEN 1 THEN 'Highest churn risk'
        WHEN 2 THEN 'Elevated churn risk'
        WHEN 3 THEN 'Moderate churn risk'
        ELSE 'Lowest churn risk'
    END AS churn_risk_label
FROM latest_comparison
ORDER BY drop_off_pct DESC, customer_id;


-- =====================================================================
-- QUERY 3: CREDIT RISK SCORING VIEW  (view_credit_risk_scoring)
-- Business use: a reusable, always-current risk label per customer.
-- Debt-to-Income (DTI) = total monthly EMI of Active/Defaulted loans
--                        divided by monthly income (income / 12) x 100.
-- EMI uses the standard amortisation formula:
--   P * r * (1+r)^n / ((1+r)^n - 1), with r = annual rate / 12 / 100.
-- Rules (evaluated top to bottom):
--   High Risk   : CIBIL < 600, OR DTI > 50%, OR 3+ missed payments in total
--   Low Risk    : CIBIL >= 740 AND DTI <= 35% AND zero missed payments
--   Medium Risk : everything else
-- =====================================================================
CREATE OR REPLACE VIEW view_credit_risk_scoring AS
WITH loan_metrics AS (
    SELECT
        customer_id,
        COUNT(*) FILTER (WHERE loan_status IN ('Active', 'Defaulted')) AS open_loan_count,
        COUNT(*) FILTER (WHERE loan_status = 'Defaulted') AS defaulted_loan_count,
        SUM(missed_payments_count) AS total_missed_payments,
        SUM(
            CASE
                WHEN loan_status IN ('Active', 'Defaulted') THEN
                    principal_amount
                    * (interest_rate / 1200.0)
                    * POWER(1 + interest_rate / 1200.0, term_months)
                    / (POWER(1 + interest_rate / 1200.0, term_months) - 1)
                ELSE 0
            END
        ) AS total_monthly_emi
    FROM loan_history
    GROUP BY customer_id
),
scored AS (
    SELECT
        c.customer_id,
        c.full_name,
        c.income,
        c.cibil_score,
        COALESCE(lm.open_loan_count, 0)      AS open_loan_count,
        COALESCE(lm.defaulted_loan_count, 0) AS defaulted_loan_count,
        COALESCE(lm.total_missed_payments, 0) AS total_missed_payments,
        ROUND(COALESCE(lm.total_monthly_emi, 0), 2) AS total_monthly_emi,
        ROUND(100.0 * COALESCE(lm.total_monthly_emi, 0) / NULLIF(c.income / 12.0, 0), 2) AS dti_ratio_pct
    FROM customers c
    LEFT JOIN loan_metrics lm ON lm.customer_id = c.customer_id
)
SELECT
    customer_id,
    full_name,
    income,
    cibil_score,
    open_loan_count,
    defaulted_loan_count,
    total_missed_payments,
    total_monthly_emi,
    dti_ratio_pct,
    CASE
        WHEN cibil_score < 600
          OR COALESCE(dti_ratio_pct, 0) > 50
          OR total_missed_payments >= 3
            THEN 'High Risk'
        WHEN cibil_score >= 740
         AND COALESCE(dti_ratio_pct, 0) <= 35
         AND total_missed_payments = 0
            THEN 'Low Risk'
        ELSE 'Medium Risk'
    END AS risk_category
FROM scored;

-- Use the view (run this part after creating it):
SELECT
    customer_id,
    full_name,
    cibil_score,
    dti_ratio_pct,
    total_missed_payments,
    risk_category
FROM view_credit_risk_scoring
ORDER BY
    CASE risk_category WHEN 'High Risk' THEN 1 WHEN 'Medium Risk' THEN 2 ELSE 3 END,
    cibil_score;


-- =====================================================================
-- QUERY 4: NON-PERFORMING ASSET (NPA) ANALYSIS BY INCOME BAND
-- Business use: shows which income segments hold the bad-loan exposure.
-- Exposure = principal of Active + Defaulted loans (Closed loans excluded).
-- NPA exposure = principal of Defaulted loans.
-- Three CTE stages:
--   1. loan_with_band : attach an income band to every open loan
--   2. band_summary   : conditional aggregation (FILTER) per band
--   3. band_metrics   : percentages and share of total NPA
-- =====================================================================
WITH loan_with_band AS (
    SELECT
        l.loan_id,
        l.customer_id,
        l.principal_amount,
        l.loan_status,
        CASE
            WHEN c.income < 500000  THEN '1. Below 5L'
            WHEN c.income < 1000000 THEN '2. 5L to 10L'
            WHEN c.income < 2000000 THEN '3. 10L to 20L'
            ELSE '4. Above 20L'
        END AS income_band
    FROM loan_history l
    INNER JOIN customers c ON c.customer_id = l.customer_id
    WHERE l.loan_status IN ('Active', 'Defaulted')
),
band_summary AS (
    SELECT
        income_band,
        COUNT(*) AS total_loans,
        COUNT(*) FILTER (WHERE loan_status = 'Defaulted') AS defaulted_loans,
        SUM(principal_amount) AS total_exposure,
        COALESCE(SUM(principal_amount) FILTER (WHERE loan_status = 'Defaulted'), 0) AS npa_exposure
    FROM loan_with_band
    GROUP BY income_band
),
band_metrics AS (
    SELECT
        income_band,
        total_loans,
        defaulted_loans,
        total_exposure,
        npa_exposure,
        ROUND(100.0 * npa_exposure / total_exposure, 2) AS npa_pct_of_band_exposure,
        ROUND(100.0 * npa_exposure / NULLIF(SUM(npa_exposure) OVER (), 0), 2) AS share_of_total_npa_pct
    FROM band_summary
)
SELECT
    income_band,
    total_loans,
    defaulted_loans,
    total_exposure,
    npa_exposure,
    npa_pct_of_band_exposure,
    share_of_total_npa_pct,
    SUM(total_exposure) OVER () AS portfolio_exposure,
    ROUND(100.0 * SUM(npa_exposure) OVER () / SUM(total_exposure) OVER (), 2) AS portfolio_gnpa_pct
FROM band_metrics
ORDER BY income_band;


-- =====================================================================
-- QUERY 5: HIGH-BALANCE DORMANT ACCOUNT FLAGGING
-- Business use: finds large idle balances for re-engagement outreach or
-- compliance review.
-- Rule: balance > 50,000 INR, account not Closed, and NO transaction in
-- the past 90 days (including accounts that never had a transaction).
-- =====================================================================
SELECT
    a.account_id,
    c.customer_id,
    c.full_name,
    a.account_type,
    a.account_status,
    a.balance,
    MAX(t.transaction_date) AS last_transaction_date,
    CASE
        WHEN MAX(t.transaction_date) IS NULL THEN NULL
        ELSE CURRENT_DATE - MAX(t.transaction_date)::date
    END AS days_since_last_transaction,
    CASE
        WHEN MAX(t.transaction_date) IS NULL THEN 'No transactions ever'
        ELSE 'Inactive over 90 days'
    END AS dormancy_reason
FROM accounts a
INNER JOIN customers c ON c.customer_id = a.customer_id
LEFT JOIN transactions t ON t.account_id = a.account_id
WHERE a.balance > 50000
  AND a.account_status <> 'Closed'
GROUP BY
    a.account_id,
    c.customer_id,
    c.full_name,
    a.account_type,
    a.account_status,
    a.balance
HAVING MAX(t.transaction_date) IS NULL
    OR MAX(t.transaction_date) < CURRENT_TIMESTAMP - INTERVAL '90 days'
ORDER BY a.balance DESC;


-- =====================================================================
-- QUERY 6: MONTH-OVER-MONTH BALANCE GROWTH TREND
-- Business use: tracks whether the bank's deposit base is growing.
-- Net change = Deposits minus (Withdrawals + Transfers) per month.
-- A month calendar fills quiet months with 0.
-- LAG()  : previous month's net change
-- LEAD() : next month's net change (NULL for the latest month)
-- Cumulative net flow shows the running balance movement; its
-- month-over-month percentage shows the growth rate.
-- =====================================================================
WITH bounds AS (
    SELECT
        DATE_TRUNC('month', MIN(transaction_date))::date AS first_month,
        DATE_TRUNC('month', MAX(transaction_date))::date AS last_month
    FROM transactions
),
calendar AS (
    SELECT GENERATE_SERIES(first_month, last_month, INTERVAL '1 month')::date AS month_start
    FROM bounds
),
monthly_flow AS (
    SELECT
        DATE_TRUNC('month', transaction_date)::date AS month_start,
        COUNT(*) AS txn_count,
        SUM(CASE WHEN transaction_type = 'Deposit' THEN amount ELSE 0 END) AS total_inflow,
        SUM(CASE WHEN transaction_type IN ('Withdrawal', 'Transfer') THEN amount ELSE 0 END) AS total_outflow
    FROM transactions
    GROUP BY DATE_TRUNC('month', transaction_date)::date
),
monthly_net AS (
    SELECT
        cal.month_start,
        COALESCE(mf.txn_count, 0) AS txn_count,
        COALESCE(mf.total_inflow, 0) AS total_inflow,
        COALESCE(mf.total_outflow, 0) AS total_outflow,
        COALESCE(mf.total_inflow, 0) - COALESCE(mf.total_outflow, 0) AS net_change
    FROM calendar cal
    LEFT JOIN monthly_flow mf ON mf.month_start = cal.month_start
),
cumulative AS (
    SELECT
        month_start,
        txn_count,
        total_inflow,
        total_outflow,
        net_change,
        SUM(net_change) OVER (ORDER BY month_start) AS cumulative_net_flow
    FROM monthly_net
)
SELECT
    month_start,
    txn_count,
    total_inflow,
    total_outflow,
    net_change,
    LAG(net_change)  OVER (ORDER BY month_start) AS prev_month_net_change,
    LEAD(net_change) OVER (ORDER BY month_start) AS next_month_net_change,
    net_change - LAG(net_change) OVER (ORDER BY month_start) AS change_vs_prev_month,
    cumulative_net_flow,
    ROUND(
        100.0 * (cumulative_net_flow - LAG(cumulative_net_flow) OVER (ORDER BY month_start))
        / NULLIF(ABS(LAG(cumulative_net_flow) OVER (ORDER BY month_start)), 0),
        2
    ) AS cumulative_growth_pct
FROM cumulative
ORDER BY month_start;
