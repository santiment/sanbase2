--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.6
-- Dumped by pg_dump version 9.6.6

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
-- Name: currencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE currencies (
    id bigint NOT NULL,
    code character varying(255) NOT NULL
);


--
-- Name: currencies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE currencies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: currencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE currencies_id_seq OWNED BY currencies.id;


--
-- Name: eth_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE eth_accounts (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    address character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: eth_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE eth_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: eth_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE eth_accounts_id_seq OWNED BY eth_accounts.id;


--
-- Name: exchange_eth_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE exchange_eth_addresses (
    id bigint NOT NULL,
    address character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    comments text
);


--
-- Name: exchange_eth_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE exchange_eth_addresses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: exchange_eth_addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE exchange_eth_addresses_id_seq OWNED BY exchange_eth_addresses.id;


--
-- Name: ico_currencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE ico_currencies (
    id bigint NOT NULL,
    ico_id bigint NOT NULL,
    currency_id bigint NOT NULL,
    amount numeric
);


--
-- Name: ico_currencies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE ico_currencies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ico_currencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE ico_currencies_id_seq OWNED BY ico_currencies.id;


--
-- Name: icos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE icos (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    start_date date,
    end_date date,
    tokens_issued_at_ico numeric,
    tokens_sold_at_ico numeric,
    minimal_cap_amount numeric,
    maximal_cap_amount numeric,
    cap_currency_id bigint,
    main_contract_address character varying(255),
    comments text,
    contract_block_number integer,
    contract_abi text,
    token_usd_ico_price numeric,
    token_eth_ico_price numeric,
    token_btc_ico_price numeric
);


--
-- Name: icos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE icos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: icos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE icos_id_seq OWNED BY icos.id;


--
-- Name: infrastructures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE infrastructures (
    id bigint NOT NULL,
    code character varying(255) NOT NULL
);


--
-- Name: infrastructures_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE infrastructures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: infrastructures_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE infrastructures_id_seq OWNED BY infrastructures.id;


--
-- Name: latest_btc_wallet_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE latest_btc_wallet_data (
    id bigint NOT NULL,
    address character varying(255) NOT NULL,
    satoshi_balance numeric NOT NULL,
    update_time timestamp without time zone NOT NULL
);


--
-- Name: latest_btc_wallet_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE latest_btc_wallet_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: latest_btc_wallet_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE latest_btc_wallet_data_id_seq OWNED BY latest_btc_wallet_data.id;


--
-- Name: latest_coinmarketcap_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE latest_coinmarketcap_data (
    id bigint NOT NULL,
    coinmarketcap_id character varying(255) NOT NULL,
    name character varying(255),
    symbol character varying(255),
    price_usd numeric,
    market_cap_usd numeric,
    update_time timestamp without time zone NOT NULL,
    rank integer,
    volume_usd numeric,
    available_supply numeric,
    total_supply numeric,
    percent_change_1h numeric,
    percent_change_24h numeric,
    percent_change_7d numeric
);


--
-- Name: latest_coinmarketcap_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE latest_coinmarketcap_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: latest_coinmarketcap_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE latest_coinmarketcap_data_id_seq OWNED BY latest_coinmarketcap_data.id;


--
-- Name: latest_eth_wallet_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE latest_eth_wallet_data (
    id bigint NOT NULL,
    address character varying(255) NOT NULL,
    balance numeric NOT NULL,
    last_incoming timestamp without time zone,
    last_outgoing timestamp without time zone,
    tx_in numeric,
    tx_out numeric,
    update_time timestamp without time zone NOT NULL
);


--
-- Name: latest_eth_wallet_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE latest_eth_wallet_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: latest_eth_wallet_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE latest_eth_wallet_data_id_seq OWNED BY latest_eth_wallet_data.id;


--
-- Name: market_segments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE market_segments (
    id bigint NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: market_segments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE market_segments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: market_segments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE market_segments_id_seq OWNED BY market_segments.id;


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
-- Name: processed_github_archives; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE processed_github_archives (
    id bigint NOT NULL,
    project_id bigint,
    archive character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: processed_github_archives_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE processed_github_archives_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: processed_github_archives_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE processed_github_archives_id_seq OWNED BY processed_github_archives.id;


--
-- Name: project; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE project (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    ticker character varying(255),
    logo_url character varying(255),
    coinmarketcap_id character varying(255),
    website_link character varying(255),
    btt_link character varying(255),
    facebook_link character varying(255),
    github_link character varying(255),
    reddit_link character varying(255),
    twitter_link character varying(255),
    whitepaper_link character varying(255),
    blog_link character varying(255),
    slack_link character varying(255),
    linkedin_link character varying(255),
    telegram_link character varying(255),
    token_address character varying(255),
    team_token_wallet character varying(255),
    market_segment_id bigint,
    infrastructure_id bigint,
    project_transparency boolean DEFAULT false NOT NULL,
    project_transparency_description text,
    project_transparency_status_id bigint,
    token_decimals integer,
    total_supply numeric
);


--
-- Name: project_btc_address; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE project_btc_address (
    id bigint NOT NULL,
    address character varying(255) NOT NULL,
    project_id bigint NOT NULL,
    project_transparency boolean DEFAULT false NOT NULL
);


--
-- Name: project_btc_address_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE project_btc_address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_btc_address_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE project_btc_address_id_seq OWNED BY project_btc_address.id;


--
-- Name: project_eth_address; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE project_eth_address (
    id bigint NOT NULL,
    address character varying(255) NOT NULL,
    project_id bigint NOT NULL,
    project_transparency boolean DEFAULT false NOT NULL
);


--
-- Name: project_eth_address_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE project_eth_address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_eth_address_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE project_eth_address_id_seq OWNED BY project_eth_address.id;


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
-- Name: project_transparency_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE project_transparency_statuses (
    id bigint NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: project_transparency_statuses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE project_transparency_statuses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_transparency_statuses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE project_transparency_statuses_id_seq OWNED BY project_transparency_statuses.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp without time zone
);


--
-- Name: user_followed_project; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE user_followed_project (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: user_followed_project_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE user_followed_project_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_followed_project_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE user_followed_project_id_seq OWNED BY user_followed_project.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE users (
    id bigint NOT NULL,
    username character varying(255),
    email character varying(255),
    salt character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: currencies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY currencies ALTER COLUMN id SET DEFAULT nextval('currencies_id_seq'::regclass);


--
-- Name: eth_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY eth_accounts ALTER COLUMN id SET DEFAULT nextval('eth_accounts_id_seq'::regclass);


--
-- Name: exchange_eth_addresses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY exchange_eth_addresses ALTER COLUMN id SET DEFAULT nextval('exchange_eth_addresses_id_seq'::regclass);


--
-- Name: ico_currencies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY ico_currencies ALTER COLUMN id SET DEFAULT nextval('ico_currencies_id_seq'::regclass);


--
-- Name: icos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY icos ALTER COLUMN id SET DEFAULT nextval('icos_id_seq'::regclass);


--
-- Name: infrastructures id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY infrastructures ALTER COLUMN id SET DEFAULT nextval('infrastructures_id_seq'::regclass);


--
-- Name: latest_btc_wallet_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY latest_btc_wallet_data ALTER COLUMN id SET DEFAULT nextval('latest_btc_wallet_data_id_seq'::regclass);


--
-- Name: latest_coinmarketcap_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY latest_coinmarketcap_data ALTER COLUMN id SET DEFAULT nextval('latest_coinmarketcap_data_id_seq'::regclass);


--
-- Name: latest_eth_wallet_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY latest_eth_wallet_data ALTER COLUMN id SET DEFAULT nextval('latest_eth_wallet_data_id_seq'::regclass);


--
-- Name: market_segments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY market_segments ALTER COLUMN id SET DEFAULT nextval('market_segments_id_seq'::regclass);


--
-- Name: notification id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification ALTER COLUMN id SET DEFAULT nextval('notification_id_seq'::regclass);


--
-- Name: notification_type id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification_type ALTER COLUMN id SET DEFAULT nextval('notification_type_id_seq'::regclass);


--
-- Name: processed_github_archives id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY processed_github_archives ALTER COLUMN id SET DEFAULT nextval('processed_github_archives_id_seq'::regclass);


--
-- Name: project id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY project ALTER COLUMN id SET DEFAULT nextval('project_id_seq'::regclass);


--
-- Name: project_btc_address id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_btc_address ALTER COLUMN id SET DEFAULT nextval('project_btc_address_id_seq'::regclass);


--
-- Name: project_eth_address id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_eth_address ALTER COLUMN id SET DEFAULT nextval('project_eth_address_id_seq'::regclass);


--
-- Name: project_transparency_statuses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_transparency_statuses ALTER COLUMN id SET DEFAULT nextval('project_transparency_statuses_id_seq'::regclass);


--
-- Name: user_followed_project id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY user_followed_project ALTER COLUMN id SET DEFAULT nextval('user_followed_project_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: currencies currencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY currencies
    ADD CONSTRAINT currencies_pkey PRIMARY KEY (id);


--
-- Name: eth_accounts eth_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY eth_accounts
    ADD CONSTRAINT eth_accounts_pkey PRIMARY KEY (id);


--
-- Name: exchange_eth_addresses exchange_eth_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY exchange_eth_addresses
    ADD CONSTRAINT exchange_eth_addresses_pkey PRIMARY KEY (id);


--
-- Name: ico_currencies ico_currencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ico_currencies
    ADD CONSTRAINT ico_currencies_pkey PRIMARY KEY (id);


--
-- Name: icos icos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY icos
    ADD CONSTRAINT icos_pkey PRIMARY KEY (id);


--
-- Name: infrastructures infrastructures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY infrastructures
    ADD CONSTRAINT infrastructures_pkey PRIMARY KEY (id);


--
-- Name: latest_btc_wallet_data latest_btc_wallet_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY latest_btc_wallet_data
    ADD CONSTRAINT latest_btc_wallet_data_pkey PRIMARY KEY (id);


--
-- Name: latest_coinmarketcap_data latest_coinmarketcap_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY latest_coinmarketcap_data
    ADD CONSTRAINT latest_coinmarketcap_data_pkey PRIMARY KEY (id);


--
-- Name: latest_eth_wallet_data latest_eth_wallet_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY latest_eth_wallet_data
    ADD CONSTRAINT latest_eth_wallet_data_pkey PRIMARY KEY (id);


--
-- Name: market_segments market_segments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY market_segments
    ADD CONSTRAINT market_segments_pkey PRIMARY KEY (id);


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
-- Name: processed_github_archives processed_github_archives_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY processed_github_archives
    ADD CONSTRAINT processed_github_archives_pkey PRIMARY KEY (id);


--
-- Name: project_btc_address project_btc_address_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_btc_address
    ADD CONSTRAINT project_btc_address_pkey PRIMARY KEY (id);


--
-- Name: project_eth_address project_eth_address_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_eth_address
    ADD CONSTRAINT project_eth_address_pkey PRIMARY KEY (id);


--
-- Name: project project_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project
    ADD CONSTRAINT project_pkey PRIMARY KEY (id);


--
-- Name: project_transparency_statuses project_transparency_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_transparency_statuses
    ADD CONSTRAINT project_transparency_statuses_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: user_followed_project user_followed_project_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY user_followed_project
    ADD CONSTRAINT user_followed_project_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: currencies_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX currencies_code_index ON currencies USING btree (code);


--
-- Name: eth_accounts_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX eth_accounts_address_index ON eth_accounts USING btree (address);


--
-- Name: exchange_eth_addresses_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX exchange_eth_addresses_address_index ON exchange_eth_addresses USING btree (address);


--
-- Name: ico_currencies_currency_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ico_currencies_currency_id_index ON ico_currencies USING btree (currency_id);


--
-- Name: ico_currencies_ico_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ico_currencies_ico_id_index ON ico_currencies USING btree (ico_id);


--
-- Name: ico_currencies_uk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ico_currencies_uk ON ico_currencies USING btree (ico_id, currency_id);


--
-- Name: infrastructures_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX infrastructures_code_index ON infrastructures USING btree (code);


--
-- Name: latest_btc_wallet_data_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX latest_btc_wallet_data_address_index ON latest_btc_wallet_data USING btree (address);


--
-- Name: latest_coinmarketcap_data_coinmarketcap_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX latest_coinmarketcap_data_coinmarketcap_id_index ON latest_coinmarketcap_data USING btree (coinmarketcap_id);


--
-- Name: latest_eth_wallet_data_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX latest_eth_wallet_data_address_index ON latest_eth_wallet_data USING btree (address);


--
-- Name: market_segments_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX market_segments_name_index ON market_segments USING btree (name);


--
-- Name: notification_project_id_type_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_project_id_type_id_index ON notification USING btree (project_id, type_id);


--
-- Name: notification_type_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX notification_type_name_index ON notification_type USING btree (name);


--
-- Name: processed_github_archives_project_id_archive_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX processed_github_archives_project_id_archive_index ON processed_github_archives USING btree (project_id, archive);


--
-- Name: project_btc_address_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_btc_address_address_index ON project_btc_address USING btree (address);


--
-- Name: project_btc_address_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_btc_address_project_id_index ON project_btc_address USING btree (project_id);


--
-- Name: project_eth_address_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_eth_address_address_index ON project_eth_address USING btree (address);


--
-- Name: project_eth_address_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_eth_address_project_id_index ON project_eth_address USING btree (project_id);


--
-- Name: project_infrastructure_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_infrastructure_id_index ON project USING btree (infrastructure_id);


--
-- Name: project_market_segment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_market_segment_id_index ON project USING btree (market_segment_id);


--
-- Name: project_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_name_index ON project USING btree (name);


--
-- Name: project_project_transparency_status_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_project_transparency_status_id_index ON project USING btree (project_transparency_status_id);


--
-- Name: project_transparency_statuses_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_transparency_statuses_name_index ON project_transparency_statuses USING btree (name);


--
-- Name: projet_user_constraint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX projet_user_constraint ON user_followed_project USING btree (project_id, user_id);


--
-- Name: users_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_index ON users USING btree (email);


--
-- Name: eth_accounts eth_accounts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY eth_accounts
    ADD CONSTRAINT eth_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: ico_currencies ico_currencies_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ico_currencies
    ADD CONSTRAINT ico_currencies_currency_id_fkey FOREIGN KEY (currency_id) REFERENCES currencies(id) ON DELETE CASCADE;


--
-- Name: ico_currencies ico_currencies_ico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ico_currencies
    ADD CONSTRAINT ico_currencies_ico_id_fkey FOREIGN KEY (ico_id) REFERENCES icos(id) ON DELETE CASCADE;


--
-- Name: icos icos_cap_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY icos
    ADD CONSTRAINT icos_cap_currency_id_fkey FOREIGN KEY (cap_currency_id) REFERENCES currencies(id);


--
-- Name: icos icos_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY icos
    ADD CONSTRAINT icos_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: notification notification_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification
    ADD CONSTRAINT notification_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: notification notification_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification
    ADD CONSTRAINT notification_type_id_fkey FOREIGN KEY (type_id) REFERENCES notification_type(id);


--
-- Name: processed_github_archives processed_github_archives_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY processed_github_archives
    ADD CONSTRAINT processed_github_archives_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: project_btc_address project_btc_address_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_btc_address
    ADD CONSTRAINT project_btc_address_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: project_eth_address project_eth_address_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_eth_address
    ADD CONSTRAINT project_eth_address_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: project project_infrastructure_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project
    ADD CONSTRAINT project_infrastructure_id_fkey FOREIGN KEY (infrastructure_id) REFERENCES infrastructures(id);


--
-- Name: project project_market_segment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project
    ADD CONSTRAINT project_market_segment_id_fkey FOREIGN KEY (market_segment_id) REFERENCES market_segments(id);


--
-- Name: project project_project_transparency_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project
    ADD CONSTRAINT project_project_transparency_status_id_fkey FOREIGN KEY (project_transparency_status_id) REFERENCES project_transparency_statuses(id);


--
-- Name: user_followed_project user_followed_project_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY user_followed_project
    ADD CONSTRAINT user_followed_project_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: user_followed_project user_followed_project_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY user_followed_project
    ADD CONSTRAINT user_followed_project_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

INSERT INTO "schema_migrations" (version) VALUES (20171008200815), (20171008203355), (20171008204451), (20171008204756), (20171008205435), (20171008205503), (20171008205547), (20171008210439), (20171017104338), (20171017104607), (20171017104817), (20171017111725), (20171017125741), (20171017132729), (20171018120438), (20171025082707), (20171106052403), (20171114151430), (20171122153530), (20171128130151), (20171128183758), (20171128183804), (20171128222957), (20171129022700), (20171130144543), (20171205103038), (20171212105707), (20171213093912), (20171213104154), (20171213115525), (20171213120408), (20171213121433), (20171213180753), (20171215133550), (20171218112921), (20171219162029), (20171224113921), (20171224114352), (20171225093503), (20171226143530), (20171228163415), (20180102111752), (20180103102329), (20180105091551), (20180108100755), (20180108110118), (20180108140221), (20180112084549), (20180112215750), (20180114093910), (20180114095310), (20180115141540);

