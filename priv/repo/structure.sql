--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.4
-- Dumped by pg_dump version 9.6.4

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
-- Name: btt; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE btt (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    link character varying(255),
    date date,
    total_reads integer,
    post_until_icostart integer,
    post_until_icoend integer,
    posts_total integer
);


--
-- Name: btt_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE btt_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: btt_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE btt_id_seq OWNED BY btt.id;


--
-- Name: countries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE countries (
    id bigint NOT NULL,
    code character varying(255) NOT NULL,
    eastern boolean,
    western boolean,
    orthodox boolean,
    sinic boolean
);


--
-- Name: countries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE countries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: countries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE countries_id_seq OWNED BY countries.id;


--
-- Name: cryptocompare_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE cryptocompare_prices (
    id bigint NOT NULL,
    id_from character varying(255) NOT NULL,
    id_to character varying(255) NOT NULL,
    price numeric
);


--
-- Name: cryptocompare_prices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE cryptocompare_prices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cryptocompare_prices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE cryptocompare_prices_id_seq OWNED BY cryptocompare_prices.id;


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
-- Name: facebook; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE facebook (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    link character varying(255),
    likes integer
);


--
-- Name: facebook_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE facebook_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: facebook_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE facebook_id_seq OWNED BY facebook.id;


--
-- Name: github; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE github (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    link character varying(255),
    commits integer,
    contributors integer
);


--
-- Name: github_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE github_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: github_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE github_id_seq OWNED BY github.id;


--
-- Name: ico_currencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE ico_currencies (
    id bigint NOT NULL,
    ico_id bigint NOT NULL,
    currency_id bigint NOT NULL
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
    tokens_issued_at_ico integer,
    tokens_sold_at_ico integer,
    tokens_team integer,
    usd_btc_icoend numeric,
    funds_raised_btc numeric,
    usd_eth_icoend numeric,
    ico_contributors integer,
    highest_bonus_percent_for_ico numeric,
    bounty_campaign boolean,
    percent_tokens_for_bounties numeric,
    minimal_cap_amount numeric,
    minimal_cap_archived boolean,
    maximal_cap_amount numeric,
    maximal_cap_archived boolean
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
    price_btc numeric,
    volume_usd_24h numeric,
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
-- Name: project; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE project (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    ticker character varying(255),
    logo_url character varying(255),
    coinmarketcap_id character varying(255),
    market_segment_id bigint,
    infrastructure_id bigint,
    geolocation_country_id bigint,
    geolocation_city character varying(255),
    website_link character varying(255),
    open_source boolean,
    cryptocompare_id character varying(255)
);


--
-- Name: project_btc_address; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE project_btc_address (
    id bigint NOT NULL,
    address character varying(255) NOT NULL,
    project_id bigint
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
    project_id bigint
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
-- Name: reddit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE reddit (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    link character varying(255),
    subscribers integer
);


--
-- Name: reddit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE reddit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reddit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE reddit_id_seq OWNED BY reddit.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp without time zone
);


--
-- Name: team_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE team_members (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    country_id bigint
);


--
-- Name: team_members_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE team_members_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE team_members_id_seq OWNED BY team_members.id;


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE teams (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    team_website integer,
    avno_linkedin_network_team numeric,
    dev_people integer,
    business_people integer,
    real_names boolean,
    pics_available boolean,
    linkedin_profiles_project integer,
    advisors integer,
    advisor_linkedin_available integer,
    av_no_linkedin_network_advisors integer
);


--
-- Name: teams_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE teams_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: teams_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE teams_id_seq OWNED BY teams.id;


--
-- Name: tracked_btc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE tracked_btc (
    id bigint NOT NULL,
    address character varying(255) NOT NULL
);


--
-- Name: tracked_btc_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tracked_btc_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tracked_btc_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE tracked_btc_id_seq OWNED BY tracked_btc.id;


--
-- Name: tracked_eth; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE tracked_eth (
    id bigint NOT NULL,
    address character varying(255) NOT NULL
);


--
-- Name: tracked_eth_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tracked_eth_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tracked_eth_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE tracked_eth_id_seq OWNED BY tracked_eth.id;


--
-- Name: twitter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE twitter (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    link character varying(255),
    joindate date,
    tweets integer,
    followers integer,
    following integer,
    likes integer
);


--
-- Name: twitter_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE twitter_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: twitter_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE twitter_id_seq OWNED BY twitter.id;


--
-- Name: whitepapers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE whitepapers (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    link character varying(255),
    authors integer,
    pages integer,
    citations integer
);


--
-- Name: whitepapers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE whitepapers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whitepapers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE whitepapers_id_seq OWNED BY whitepapers.id;


--
-- Name: btt id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY btt ALTER COLUMN id SET DEFAULT nextval('btt_id_seq'::regclass);


--
-- Name: countries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY countries ALTER COLUMN id SET DEFAULT nextval('countries_id_seq'::regclass);


--
-- Name: cryptocompare_prices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY cryptocompare_prices ALTER COLUMN id SET DEFAULT nextval('cryptocompare_prices_id_seq'::regclass);


--
-- Name: currencies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY currencies ALTER COLUMN id SET DEFAULT nextval('currencies_id_seq'::regclass);


--
-- Name: facebook id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY facebook ALTER COLUMN id SET DEFAULT nextval('facebook_id_seq'::regclass);


--
-- Name: github id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY github ALTER COLUMN id SET DEFAULT nextval('github_id_seq'::regclass);


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
-- Name: reddit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY reddit ALTER COLUMN id SET DEFAULT nextval('reddit_id_seq'::regclass);


--
-- Name: team_members id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY team_members ALTER COLUMN id SET DEFAULT nextval('team_members_id_seq'::regclass);


--
-- Name: teams id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY teams ALTER COLUMN id SET DEFAULT nextval('teams_id_seq'::regclass);


--
-- Name: tracked_btc id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY tracked_btc ALTER COLUMN id SET DEFAULT nextval('tracked_btc_id_seq'::regclass);


--
-- Name: tracked_eth id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY tracked_eth ALTER COLUMN id SET DEFAULT nextval('tracked_eth_id_seq'::regclass);


--
-- Name: twitter id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY twitter ALTER COLUMN id SET DEFAULT nextval('twitter_id_seq'::regclass);


--
-- Name: whitepapers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY whitepapers ALTER COLUMN id SET DEFAULT nextval('whitepapers_id_seq'::regclass);


--
-- Name: btt btt_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY btt
    ADD CONSTRAINT btt_pkey PRIMARY KEY (id);


--
-- Name: countries countries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY countries
    ADD CONSTRAINT countries_pkey PRIMARY KEY (id);


--
-- Name: cryptocompare_prices cryptocompare_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY cryptocompare_prices
    ADD CONSTRAINT cryptocompare_prices_pkey PRIMARY KEY (id);


--
-- Name: currencies currencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY currencies
    ADD CONSTRAINT currencies_pkey PRIMARY KEY (id);


--
-- Name: facebook facebook_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY facebook
    ADD CONSTRAINT facebook_pkey PRIMARY KEY (id);


--
-- Name: github github_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY github
    ADD CONSTRAINT github_pkey PRIMARY KEY (id);


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
-- Name: reddit reddit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reddit
    ADD CONSTRAINT reddit_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: team_members team_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY team_members
    ADD CONSTRAINT team_members_pkey PRIMARY KEY (id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: tracked_btc tracked_btc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY tracked_btc
    ADD CONSTRAINT tracked_btc_pkey PRIMARY KEY (id);


--
-- Name: tracked_eth tracked_eth_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY tracked_eth
    ADD CONSTRAINT tracked_eth_pkey PRIMARY KEY (id);


--
-- Name: twitter twitter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY twitter
    ADD CONSTRAINT twitter_pkey PRIMARY KEY (id);


--
-- Name: whitepapers whitepapers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY whitepapers
    ADD CONSTRAINT whitepapers_pkey PRIMARY KEY (id);


--
-- Name: btt_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX btt_project_id_index ON btt USING btree (project_id);


--
-- Name: countries_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX countries_code_index ON countries USING btree (code);


--
-- Name: cryptocompare_id_from_to_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cryptocompare_id_from_to_index ON cryptocompare_prices USING btree (id_from, id_to);


--
-- Name: currencies_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX currencies_code_index ON currencies USING btree (code);


--
-- Name: facebook_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX facebook_project_id_index ON facebook USING btree (project_id);


--
-- Name: github_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX github_project_id_index ON github USING btree (project_id);


--
-- Name: ico_currencies_currency_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ico_currencies_currency_id_index ON ico_currencies USING btree (currency_id);


--
-- Name: ico_currencies_ico_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ico_currencies_ico_id_index ON ico_currencies USING btree (ico_id);


--
-- Name: icos_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX icos_project_id_index ON icos USING btree (project_id);


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
-- Name: project_geolocation_country_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_geolocation_country_id_index ON project USING btree (geolocation_country_id);


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
-- Name: reddit_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reddit_project_id_index ON reddit USING btree (project_id);


--
-- Name: team_members_country_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX team_members_country_id_index ON team_members USING btree (country_id);


--
-- Name: team_members_team_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX team_members_team_id_index ON team_members USING btree (team_id);


--
-- Name: teams_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX teams_project_id_index ON teams USING btree (project_id);


--
-- Name: tracked_btc_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tracked_btc_address_index ON tracked_btc USING btree (address);


--
-- Name: tracked_eth_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tracked_eth_address_index ON tracked_eth USING btree (address);


--
-- Name: twitter_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX twitter_project_id_index ON twitter USING btree (project_id);


--
-- Name: whitepapers_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX whitepapers_project_id_index ON whitepapers USING btree (project_id);


--
-- Name: btt btt_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY btt
    ADD CONSTRAINT btt_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: facebook facebook_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY facebook
    ADD CONSTRAINT facebook_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: github github_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY github
    ADD CONSTRAINT github_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: ico_currencies ico_currencies_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ico_currencies
    ADD CONSTRAINT ico_currencies_currency_id_fkey FOREIGN KEY (currency_id) REFERENCES currencies(id);


--
-- Name: ico_currencies ico_currencies_ico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ico_currencies
    ADD CONSTRAINT ico_currencies_ico_id_fkey FOREIGN KEY (ico_id) REFERENCES icos(id);


--
-- Name: icos icos_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY icos
    ADD CONSTRAINT icos_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


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
-- Name: project project_geolocation_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project
    ADD CONSTRAINT project_geolocation_country_id_fkey FOREIGN KEY (geolocation_country_id) REFERENCES countries(id);


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
-- Name: reddit reddit_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reddit
    ADD CONSTRAINT reddit_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: team_members team_members_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY team_members
    ADD CONSTRAINT team_members_country_id_fkey FOREIGN KEY (country_id) REFERENCES countries(id);


--
-- Name: team_members team_members_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY team_members
    ADD CONSTRAINT team_members_team_id_fkey FOREIGN KEY (team_id) REFERENCES teams(id);


--
-- Name: teams teams_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY teams
    ADD CONSTRAINT teams_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: twitter twitter_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY twitter
    ADD CONSTRAINT twitter_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- Name: whitepapers whitepapers_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY whitepapers
    ADD CONSTRAINT whitepapers_project_id_fkey FOREIGN KEY (project_id) REFERENCES project(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

INSERT INTO "schema_migrations" (version) VALUES (20171008200815), (20171008203355), (20171008204451), (20171008204756), (20171008205435), (20171008205503), (20171008205547), (20171008210439), (20171017104338), (20171017104607), (20171017104817), (20171017105339), (20171017111725), (20171017125741), (20171017130527), (20171017130741), (20171017131940), (20171017132003), (20171017132015), (20171017132031), (20171017132040), (20171017132049), (20171017132729), (20171017143803), (20171017144834), (20171018120438), (20171025082707);

