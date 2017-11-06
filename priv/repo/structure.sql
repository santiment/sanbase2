--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.1
-- Dumped by pg_dump version 9.6.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: latest_btc_wallet_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE latest_btc_wallet_data (
    address text NOT NULL,
    satoshi_balance real NOT NULL,
    update_time timestamp without time zone NOT NULL
);


--
-- Name: latest_coinmarketcap_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE latest_coinmarketcap_data (
    id text NOT NULL,
    name text,
    symbol text,
    price_usd numeric,
    market_cap_usd numeric,
    update_time timestamp without time zone NOT NULL
);


--
-- Name: latest_eth_wallet_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE latest_eth_wallet_data (
    address text NOT NULL,
    balance real NOT NULL,
    last_incoming timestamp without time zone,
    last_outgoing timestamp without time zone,
    tx_in real,
    tx_out real,
    update_time timestamp without time zone NOT NULL
);


--
-- Name: notification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE notification (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    type_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: notification_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE notification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE notification_id_seq OWNED BY notification.id;


--
-- Name: notification_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE notification_type (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: notification_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE notification_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE notification_type_id_seq OWNED BY notification_type.id;


--
-- Name: project; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE project (
    id integer NOT NULL,
    name text NOT NULL,
    ticker text NOT NULL,
    logo_url text,
    coinmarketcap_id text
);


--
-- Name: project_btc_address; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE project_btc_address (
    address text NOT NULL,
    project_id integer
);


--
-- Name: project_eth_address; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE project_eth_address (
    address text NOT NULL,
    project_id integer
);


--
-- Name: project_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE project_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE project_id_seq OWNED BY project.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp without time zone
);


--
-- Name: tracked_btc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE tracked_btc (
    address text NOT NULL
);


--
-- Name: tracked_eth; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE tracked_eth (
    address text NOT NULL
);


--
-- Name: notification id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification ALTER COLUMN id SET DEFAULT nextval('notification_id_seq'::regclass);


--
-- Name: notification_type id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification_type ALTER COLUMN id SET DEFAULT nextval('notification_type_id_seq'::regclass);


--
-- Name: project id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY project ALTER COLUMN id SET DEFAULT nextval('project_id_seq'::regclass);


--
-- Name: latest_btc_wallet_data latest_btc_wallet_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY latest_btc_wallet_data
    ADD CONSTRAINT latest_btc_wallet_data_pkey PRIMARY KEY (address);


--
-- Name: latest_coinmarketcap_data latest_coinmarketcap_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY latest_coinmarketcap_data
    ADD CONSTRAINT latest_coinmarketcap_data_pkey PRIMARY KEY (id);


--
-- Name: latest_eth_wallet_data latest_eth_wallet_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY latest_eth_wallet_data
    ADD CONSTRAINT latest_eth_wallet_data_pkey PRIMARY KEY (address);


--
-- Name: notification notification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification
    ADD CONSTRAINT notification_pkey PRIMARY KEY (id);


--
-- Name: notification_type notification_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification_type
    ADD CONSTRAINT notification_type_pkey PRIMARY KEY (id);


--
-- Name: project_btc_address project_btc_address_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_btc_address
    ADD CONSTRAINT project_btc_address_pkey PRIMARY KEY (address);


--
-- Name: project_eth_address project_eth_address_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_eth_address
    ADD CONSTRAINT project_eth_address_pkey PRIMARY KEY (address);


--
-- Name: project project_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project
    ADD CONSTRAINT project_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: tracked_btc tracked_btc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY tracked_btc
    ADD CONSTRAINT tracked_btc_pkey PRIMARY KEY (address);


--
-- Name: tracked_eth tracked_eth_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY tracked_eth
    ADD CONSTRAINT tracked_eth_pkey PRIMARY KEY (address);


--
-- Name: notification_project_id_type_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_project_id_type_id_index ON notification USING btree (project_id, type_id);


--
-- Name: notification_type_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX notification_type_name_index ON notification_type USING btree (name);


--
-- Name: project_btc_address_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_btc_address_project_id_index ON project_btc_address USING btree (project_id);


--
-- Name: project_coinmarketcap_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_coinmarketcap_id_index ON project USING btree (coinmarketcap_id);


--
-- Name: project_eth_address_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_eth_address_project_id_index ON project_eth_address USING btree (project_id);


--
-- Name: project_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_name_index ON project USING btree (name);


--
-- Name: notification notification_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification
    ADD CONSTRAINT notification_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id);


--
-- Name: notification notification_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification
    ADD CONSTRAINT notification_type_id_fkey FOREIGN KEY (type_id) REFERENCES notification_type(id);


--
-- Name: project_btc_address project_btc_address_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_btc_address
    ADD CONSTRAINT project_btc_address_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id);


--
-- Name: project_eth_address project_eth_address_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_eth_address
    ADD CONSTRAINT project_eth_address_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id);


--
-- PostgreSQL database dump complete
--

INSERT INTO "schema_migrations" (version) VALUES (20170911162322), (20171008200815), (20171008203355), (20171008204451), (20171008204756), (20171008205435), (20171008205503), (20171008205547), (20171008210439), (20171018120438), (20171018141238), (20171106052403);

