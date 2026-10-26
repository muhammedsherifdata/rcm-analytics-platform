/* 01_create_staging.sql
   Creates the RCM database, the stg schema and all-text staging tables.
   Column order MUST match the CSV header exactly. */
IF DB_ID('RCM') IS NULL CREATE DATABASE RCM;
GO
USE RCM;
GO
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('clean') IS NULL EXEC('CREATE SCHEMA clean');
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw');
GO

DROP TABLE IF EXISTS stg.payers, stg.providers, stg.patients, stg.claims, stg.remittances, stg.denials;

CREATE TABLE stg.payers (
    payer_id NVARCHAR(50), payer_name NVARCHAR(200), country NVARCHAR(50), payer_type NVARCHAR(50));

CREATE TABLE stg.providers (
    provider_id NVARCHAR(50), provider_name NVARCHAR(200), city NVARCHAR(100),
    country NVARCHAR(50), provider_type NVARCHAR(50));

CREATE TABLE stg.patients (
    patient_id NVARCHAR(50), gender NVARCHAR(50), birth_date NVARCHAR(50));

CREATE TABLE stg.claims (
    claim_id NVARCHAR(50), patient_id NVARCHAR(50), provider_id NVARCHAR(50), payer_id NVARCHAR(50),
    payer_name_submitted NVARCHAR(200), claim_type NVARCHAR(50), cpt_code NVARCHAR(50),
    primary_icd10 NVARCHAR(50), service_date NVARCHAR(50), submission_date NVARCHAR(50),
    claim_amount NVARCHAR(50), prior_auth_required NVARCHAR(50), prior_auth_obtained NVARCHAR(50),
    eligibility_verified NVARCHAR(50), claim_status NVARCHAR(50));

CREATE TABLE stg.remittances (
    remittance_id NVARCHAR(50), claim_id NVARCHAR(50), payment_date NVARCHAR(50),
    paid_amount NVARCHAR(50), patient_responsibility NVARCHAR(50),
    contractual_adjustment NVARCHAR(50), payment_type NVARCHAR(50));

CREATE TABLE stg.denials (
    denial_id NVARCHAR(50), claim_id NVARCHAR(50), denial_date NVARCHAR(50),
    denial_code NVARCHAR(50), denial_reason NVARCHAR(200), denied_amount NVARCHAR(50),
    appealed NVARCHAR(50), appeal_date NVARCHAR(50), appeal_outcome NVARCHAR(50),
    recovered_amount NVARCHAR(50));
GO
