--
-- PostgreSQL database dump
--

-- Dumped from database version 10.5
-- Dumped by pg_dump version 10.5

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: timescaledb; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;


--
-- Name: EXTENSION timescaledb; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION timescaledb IS 'Enables scalable inserts and complex queries for time-series data';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: eth_burn_rate; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_burn_rate (
    "timestamp" timestamp without time zone NOT NULL,
    contract_address character varying(255) NOT NULL,
    burn_rate double precision
);


--
-- Name: eth_coin_circulation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_coin_circulation (
    "timestamp" timestamp without time zone NOT NULL,
    contract_address character varying(255) NOT NULL,
    "_-1d" double precision
);


--
-- Name: eth_daily_active_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_daily_active_addresses (
    "timestamp" timestamp without time zone NOT NULL,
    contract_address character varying(255) NOT NULL,
    active_addresses integer
);


--
-- Name: eth_exchange_funds_flow; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_exchange_funds_flow (
    "timestamp" timestamp without time zone NOT NULL,
    contract_address character varying(255) NOT NULL,
    incoming_exchange_funds double precision,
    outgoing_exchange_funds double precision
);


--
-- Name: eth_transaction_volume; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_transaction_volume (
    "timestamp" timestamp without time zone NOT NULL,
    contract_address character varying(255) NOT NULL,
    transaction_volume double precision
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp without time zone
);


--
-- Name: eth_burn_rate eth_burn_rate_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_burn_rate
    ADD CONSTRAINT eth_burn_rate_pkey PRIMARY KEY ("timestamp", contract_address);


--
-- Name: eth_coin_circulation eth_coin_circulation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_coin_circulation
    ADD CONSTRAINT eth_coin_circulation_pkey PRIMARY KEY ("timestamp", contract_address);


--
-- Name: eth_daily_active_addresses eth_daily_active_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_daily_active_addresses
    ADD CONSTRAINT eth_daily_active_addresses_pkey PRIMARY KEY ("timestamp", contract_address);


--
-- Name: eth_exchange_funds_flow eth_exchange_funds_flow_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_exchange_funds_flow
    ADD CONSTRAINT eth_exchange_funds_flow_pkey PRIMARY KEY ("timestamp", contract_address);


--
-- Name: eth_transaction_volume eth_transaction_volume_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_transaction_volume
    ADD CONSTRAINT eth_transaction_volume_pkey PRIMARY KEY ("timestamp", contract_address);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- PostgreSQL database dump complete
--

INSERT INTO public."schema_migrations" (version) VALUES (20180731110511), (20180802132742), (20180802142827), (20180803131502), (20181203131440);

