--
-- PostgreSQL database dump
--

-- Dumped from database version 11.5
-- Dumped by pg_dump version 11.5

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
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
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: color; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.color AS ENUM (
    'none',
    'blue',
    'red',
    'green',
    'yellow',
    'grey',
    'black'
);


--
-- Name: status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.status AS ENUM (
    'initial',
    'incomplete',
    'incomplete_expired',
    'trialing',
    'active',
    'past_due',
    'canceled',
    'unpaid'
);


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: currencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.currencies (
    id bigint NOT NULL,
    code character varying(255) NOT NULL
);


--
-- Name: currencies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.currencies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: currencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.currencies_id_seq OWNED BY public.currencies.id;


--
-- Name: eth_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_accounts (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    address character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: eth_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.eth_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: eth_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.eth_accounts_id_seq OWNED BY public.eth_accounts.id;


--
-- Name: eth_coin_circulation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_coin_circulation (
    "timestamp" timestamp without time zone NOT NULL,
    contract_address character varying(255) NOT NULL,
    "_-1d" double precision
);


--
-- Name: exchange_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_addresses (
    id bigint NOT NULL,
    address character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    comments text,
    source text,
    is_dex boolean,
    infrastructure_id bigint,
    computed_at timestamp without time zone
);


--
-- Name: exchange_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.exchange_addresses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: exchange_addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.exchange_addresses_id_seq OWNED BY public.exchange_addresses.id;


--
-- Name: featured_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.featured_items (
    id bigint NOT NULL,
    post_id bigint,
    user_list_id bigint,
    user_trigger_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT only_one_fk CHECK ((((
CASE
    WHEN (post_id IS NULL) THEN 0
    ELSE 1
END +
CASE
    WHEN (user_list_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (user_trigger_id IS NULL) THEN 0
    ELSE 1
END) = 1))
);


--
-- Name: featured_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.featured_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: featured_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.featured_items_id_seq OWNED BY public.featured_items.id;


--
-- Name: github_organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.github_organizations (
    id bigint NOT NULL,
    organization character varying(255),
    project_id bigint
);


--
-- Name: github_organizations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.github_organizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: github_organizations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.github_organizations_id_seq OWNED BY public.github_organizations.id;


--
-- Name: ico_currencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ico_currencies (
    id bigint NOT NULL,
    ico_id bigint NOT NULL,
    currency_id bigint NOT NULL,
    amount numeric
);


--
-- Name: ico_currencies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ico_currencies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ico_currencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ico_currencies_id_seq OWNED BY public.ico_currencies.id;


--
-- Name: icos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.icos (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    start_date date,
    end_date date,
    tokens_issued_at_ico numeric,
    tokens_sold_at_ico numeric,
    minimal_cap_amount numeric,
    maximal_cap_amount numeric,
    cap_currency_id bigint,
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

CREATE SEQUENCE public.icos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: icos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.icos_id_seq OWNED BY public.icos.id;


--
-- Name: infrastructures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.infrastructures (
    id bigint NOT NULL,
    code character varying(255) NOT NULL
);


--
-- Name: infrastructures_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.infrastructures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: infrastructures_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.infrastructures_id_seq OWNED BY public.infrastructures.id;


--
-- Name: latest_btc_wallet_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.latest_btc_wallet_data (
    id bigint NOT NULL,
    address public.citext NOT NULL,
    satoshi_balance numeric NOT NULL,
    update_time timestamp without time zone NOT NULL
);


--
-- Name: latest_btc_wallet_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.latest_btc_wallet_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: latest_btc_wallet_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.latest_btc_wallet_data_id_seq OWNED BY public.latest_btc_wallet_data.id;


--
-- Name: latest_coinmarketcap_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.latest_coinmarketcap_data (
    id bigint NOT NULL,
    coinmarketcap_id character varying(255) NOT NULL,
    name character varying(255),
    symbol character varying(255),
    price_usd numeric,
    market_cap_usd numeric,
    update_time timestamp without time zone,
    rank integer,
    volume_usd numeric,
    available_supply numeric,
    total_supply numeric,
    percent_change_1h numeric,
    percent_change_24h numeric,
    percent_change_7d numeric,
    price_btc numeric,
    logo_hash character varying(255),
    logo_updated_at timestamp without time zone
);


--
-- Name: latest_coinmarketcap_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.latest_coinmarketcap_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: latest_coinmarketcap_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.latest_coinmarketcap_data_id_seq OWNED BY public.latest_coinmarketcap_data.id;


--
-- Name: list_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_items (
    user_list_id bigint NOT NULL,
    project_id bigint NOT NULL
);


--
-- Name: market_segments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.market_segments (
    id bigint NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: market_segments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.market_segments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: market_segments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.market_segments_id_seq OWNED BY public.market_segments.id;


--
-- Name: notification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    type_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    data text
);


--
-- Name: notification_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_id_seq OWNED BY public.notification.id;


--
-- Name: notification_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_type (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: notification_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_type_id_seq OWNED BY public.notification_type.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    type_id bigint NOT NULL,
    data character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notifications_id_seq OWNED BY public.notifications.id;


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    amount integer NOT NULL,
    currency character varying(255) NOT NULL,
    "interval" character varying(255) NOT NULL,
    product_id bigint NOT NULL,
    stripe_id character varying(255)
);


--
-- Name: plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.plans_id_seq OWNED BY public.plans.id;


--
-- Name: polls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.polls (
    id bigint NOT NULL,
    start_at timestamp without time zone NOT NULL,
    end_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: polls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.polls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: polls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.polls_id_seq OWNED BY public.polls.id;


--
-- Name: post_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_images (
    id bigint NOT NULL,
    file_name text,
    image_url text NOT NULL,
    content_hash text NOT NULL,
    hash_algorithm text NOT NULL,
    post_id bigint
);


--
-- Name: post_images_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.post_images_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: post_images_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.post_images_id_seq OWNED BY public.post_images.id;


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id bigint NOT NULL,
    poll_id bigint NOT NULL,
    user_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    link text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    state character varying(255),
    moderation_comment character varying(255),
    short_desc text,
    text text,
    ready_state character varying(255) DEFAULT 'draft'::character varying,
    discourse_topic_url character varying(255),
    published_at timestamp without time zone
);


--
-- Name: posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.posts_id_seq OWNED BY public.posts.id;


--
-- Name: posts_projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts_projects (
    id bigint NOT NULL,
    post_id bigint,
    project_id bigint
);


--
-- Name: posts_projects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.posts_projects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: posts_projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.posts_projects_id_seq OWNED BY public.posts_projects.id;


--
-- Name: posts_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts_tags (
    id bigint NOT NULL,
    post_id bigint,
    tag_id bigint
);


--
-- Name: posts_tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.posts_tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: posts_tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.posts_tags_id_seq OWNED BY public.posts_tags.id;


--
-- Name: processed_github_archives; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processed_github_archives (
    id bigint NOT NULL,
    project_id bigint,
    archive character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: processed_github_archives_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.processed_github_archives_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: processed_github_archives_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.processed_github_archives_id_seq OWNED BY public.processed_github_archives.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    stripe_id character varying(255)
);


--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: project; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project (
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
    total_supply numeric,
    description text,
    email character varying(255),
    main_contract_address character varying(255),
    long_description text,
    slug character varying(255)
);


--
-- Name: project_btc_address; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_btc_address (
    id bigint NOT NULL,
    address public.citext NOT NULL,
    project_id bigint NOT NULL,
    source text,
    comments text
);


--
-- Name: project_btc_address_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_btc_address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_btc_address_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_btc_address_id_seq OWNED BY public.project_btc_address.id;


--
-- Name: project_eth_address; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_eth_address (
    id bigint NOT NULL,
    address public.citext NOT NULL,
    project_id bigint NOT NULL,
    source text,
    comments text
);


--
-- Name: project_eth_address_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_eth_address_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_eth_address_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_eth_address_id_seq OWNED BY public.project_eth_address.id;


--
-- Name: project_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_id_seq OWNED BY public.project.id;


--
-- Name: project_market_segments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_market_segments (
    id bigint NOT NULL,
    project_id bigint,
    market_segment_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: project_market_segments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_market_segments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_market_segments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_market_segments_id_seq OWNED BY public.project_market_segments.id;


--
-- Name: project_social_volume_query; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_social_volume_query (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    query text
);


--
-- Name: project_social_volume_query_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_social_volume_query_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_social_volume_query_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_social_volume_query_id_seq OWNED BY public.project_social_volume_query.id;


--
-- Name: project_transparency_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_transparency_statuses (
    id bigint NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: project_transparency_statuses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_transparency_statuses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_transparency_statuses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_transparency_statuses_id_seq OWNED BY public.project_transparency_statuses.id;


--
-- Name: schedule_rescrape_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schedule_rescrape_prices (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    "from" timestamp without time zone NOT NULL,
    "to" timestamp without time zone NOT NULL,
    original_last_updated timestamp without time zone,
    in_progress boolean NOT NULL,
    finished boolean NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: schedule_rescrape_prices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.schedule_rescrape_prices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schedule_rescrape_prices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.schedule_rescrape_prices_id_seq OWNED BY public.schedule_rescrape_prices.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp without time zone
);


--
-- Name: signals_historical_activity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.signals_historical_activity (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    user_trigger_id bigint NOT NULL,
    payload jsonb NOT NULL,
    triggered_at timestamp without time zone NOT NULL
);


--
-- Name: signals_historical_activity_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.signals_historical_activity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: signals_historical_activity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.signals_historical_activity_id_seq OWNED BY public.signals_historical_activity.id;


--
-- Name: source_slug_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.source_slug_mappings (
    id bigint NOT NULL,
    source character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    project_id bigint
);


--
-- Name: source_slug_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.source_slug_mappings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_slug_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.source_slug_mappings_id_seq OWNED BY public.source_slug_mappings.id;


--
-- Name: stripe_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stripe_events (
    event_id character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    payload jsonb NOT NULL,
    is_processed boolean DEFAULT false,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    plan_id bigint NOT NULL,
    stripe_id character varying(255),
    cancel_at_period_end boolean DEFAULT false NOT NULL,
    current_period_end timestamp without time zone,
    status public.status DEFAULT 'initial'::public.status NOT NULL
);


--
-- Name: subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscriptions_id_seq OWNED BY public.subscriptions.id;


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id bigint NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tags_id_seq OWNED BY public.tags.id;


--
-- Name: telegram_user_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telegram_user_tokens (
    user_id bigint NOT NULL,
    token character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: timeline_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.timeline_events (
    id bigint NOT NULL,
    event_type character varying(255),
    user_id bigint,
    post_id bigint,
    user_list_id bigint,
    user_trigger_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT only_one_fk CHECK ((((
CASE
    WHEN (post_id IS NULL) THEN 0
    ELSE 1
END +
CASE
    WHEN (user_list_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (user_trigger_id IS NULL) THEN 0
    ELSE 1
END) = 1))
);


--
-- Name: timeline_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.timeline_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: timeline_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.timeline_events_id_seq OWNED BY public.timeline_events.id;


--
-- Name: user_api_key_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_api_key_tokens (
    id bigint NOT NULL,
    user_id bigint,
    token character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: user_api_key_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_api_key_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_api_key_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_api_key_tokens_id_seq OWNED BY public.user_api_key_tokens.id;


--
-- Name: user_followers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_followers (
    user_id bigint NOT NULL,
    follower_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT user_cannot_follow_self CHECK ((user_id <> follower_id))
);


--
-- Name: user_lists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_lists (
    id bigint NOT NULL,
    name character varying(255),
    is_public boolean DEFAULT false,
    color public.color,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    function jsonb DEFAULT '{"args": [], "name": "empty"}'::jsonb,
    slug character varying(255)
);


--
-- Name: user_lists_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_lists_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_lists_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_lists_id_seq OWNED BY public.user_lists.id;


--
-- Name: user_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_settings (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    settings jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: user_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_settings_id_seq OWNED BY public.user_settings.id;


--
-- Name: user_triggers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_triggers (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    trigger jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: user_triggers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_triggers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_triggers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_triggers_id_seq OWNED BY public.user_triggers.id;


--
-- Name: user_triggers_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_triggers_tags (
    id bigint NOT NULL,
    user_trigger_id bigint,
    tag_id bigint
);


--
-- Name: user_triggers_tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_triggers_tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_triggers_tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_triggers_tags_id_seq OWNED BY public.user_triggers_tags.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    username character varying(255),
    email character varying(255),
    salt character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    san_tokens integer,
    san_balance numeric,
    san_balance_updated_at timestamp without time zone,
    email_token character varying(255),
    email_token_generated_at timestamp without time zone,
    email_token_validated_at timestamp without time zone,
    consent_id character varying(255),
    test_san_balance numeric,
    privacy_policy_accepted boolean DEFAULT false NOT NULL,
    marketing_accepted boolean DEFAULT false NOT NULL,
    email_candidate character varying(255),
    email_candidate_token character varying(255),
    email_candidate_token_generated_at timestamp without time zone,
    email_candidate_token_validated_at timestamp without time zone,
    stripe_customer_id character varying(255)
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.votes (
    id bigint NOT NULL,
    post_id bigint NOT NULL,
    user_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: votes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.votes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: votes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.votes_id_seq OWNED BY public.votes.id;


--
-- Name: watchlist_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.watchlist_settings (
    user_id bigint NOT NULL,
    watchlist_id bigint NOT NULL,
    settings jsonb
);


--
-- Name: currencies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.currencies ALTER COLUMN id SET DEFAULT nextval('public.currencies_id_seq'::regclass);


--
-- Name: eth_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_accounts ALTER COLUMN id SET DEFAULT nextval('public.eth_accounts_id_seq'::regclass);


--
-- Name: exchange_addresses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_addresses ALTER COLUMN id SET DEFAULT nextval('public.exchange_addresses_id_seq'::regclass);


--
-- Name: featured_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items ALTER COLUMN id SET DEFAULT nextval('public.featured_items_id_seq'::regclass);


--
-- Name: github_organizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_organizations ALTER COLUMN id SET DEFAULT nextval('public.github_organizations_id_seq'::regclass);


--
-- Name: ico_currencies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ico_currencies ALTER COLUMN id SET DEFAULT nextval('public.ico_currencies_id_seq'::regclass);


--
-- Name: icos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.icos ALTER COLUMN id SET DEFAULT nextval('public.icos_id_seq'::regclass);


--
-- Name: infrastructures id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructures ALTER COLUMN id SET DEFAULT nextval('public.infrastructures_id_seq'::regclass);


--
-- Name: latest_btc_wallet_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.latest_btc_wallet_data ALTER COLUMN id SET DEFAULT nextval('public.latest_btc_wallet_data_id_seq'::regclass);


--
-- Name: latest_coinmarketcap_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.latest_coinmarketcap_data ALTER COLUMN id SET DEFAULT nextval('public.latest_coinmarketcap_data_id_seq'::regclass);


--
-- Name: market_segments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_segments ALTER COLUMN id SET DEFAULT nextval('public.market_segments_id_seq'::regclass);


--
-- Name: notification id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification ALTER COLUMN id SET DEFAULT nextval('public.notification_id_seq'::regclass);


--
-- Name: notification_type id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_type ALTER COLUMN id SET DEFAULT nextval('public.notification_type_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- Name: plans id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans ALTER COLUMN id SET DEFAULT nextval('public.plans_id_seq'::regclass);


--
-- Name: polls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polls ALTER COLUMN id SET DEFAULT nextval('public.polls_id_seq'::regclass);


--
-- Name: post_images id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_images ALTER COLUMN id SET DEFAULT nextval('public.post_images_id_seq'::regclass);


--
-- Name: posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts ALTER COLUMN id SET DEFAULT nextval('public.posts_id_seq'::regclass);


--
-- Name: posts_projects id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_projects ALTER COLUMN id SET DEFAULT nextval('public.posts_projects_id_seq'::regclass);


--
-- Name: posts_tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_tags ALTER COLUMN id SET DEFAULT nextval('public.posts_tags_id_seq'::regclass);


--
-- Name: processed_github_archives id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_github_archives ALTER COLUMN id SET DEFAULT nextval('public.processed_github_archives_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: project id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project ALTER COLUMN id SET DEFAULT nextval('public.project_id_seq'::regclass);


--
-- Name: project_btc_address id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_btc_address ALTER COLUMN id SET DEFAULT nextval('public.project_btc_address_id_seq'::regclass);


--
-- Name: project_eth_address id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_eth_address ALTER COLUMN id SET DEFAULT nextval('public.project_eth_address_id_seq'::regclass);


--
-- Name: project_market_segments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_market_segments ALTER COLUMN id SET DEFAULT nextval('public.project_market_segments_id_seq'::regclass);


--
-- Name: project_social_volume_query id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_social_volume_query ALTER COLUMN id SET DEFAULT nextval('public.project_social_volume_query_id_seq'::regclass);


--
-- Name: project_transparency_statuses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_transparency_statuses ALTER COLUMN id SET DEFAULT nextval('public.project_transparency_statuses_id_seq'::regclass);


--
-- Name: schedule_rescrape_prices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_rescrape_prices ALTER COLUMN id SET DEFAULT nextval('public.schedule_rescrape_prices_id_seq'::regclass);


--
-- Name: signals_historical_activity id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signals_historical_activity ALTER COLUMN id SET DEFAULT nextval('public.signals_historical_activity_id_seq'::regclass);


--
-- Name: source_slug_mappings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_slug_mappings ALTER COLUMN id SET DEFAULT nextval('public.source_slug_mappings_id_seq'::regclass);


--
-- Name: subscriptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions ALTER COLUMN id SET DEFAULT nextval('public.subscriptions_id_seq'::regclass);


--
-- Name: tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags ALTER COLUMN id SET DEFAULT nextval('public.tags_id_seq'::regclass);


--
-- Name: timeline_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events ALTER COLUMN id SET DEFAULT nextval('public.timeline_events_id_seq'::regclass);


--
-- Name: user_api_key_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_api_key_tokens ALTER COLUMN id SET DEFAULT nextval('public.user_api_key_tokens_id_seq'::regclass);


--
-- Name: user_lists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lists ALTER COLUMN id SET DEFAULT nextval('public.user_lists_id_seq'::regclass);


--
-- Name: user_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_settings ALTER COLUMN id SET DEFAULT nextval('public.user_settings_id_seq'::regclass);


--
-- Name: user_triggers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_triggers ALTER COLUMN id SET DEFAULT nextval('public.user_triggers_id_seq'::regclass);


--
-- Name: user_triggers_tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_triggers_tags ALTER COLUMN id SET DEFAULT nextval('public.user_triggers_tags_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: votes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes ALTER COLUMN id SET DEFAULT nextval('public.votes_id_seq'::regclass);


--
-- Name: currencies currencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.currencies
    ADD CONSTRAINT currencies_pkey PRIMARY KEY (id);


--
-- Name: eth_accounts eth_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_accounts
    ADD CONSTRAINT eth_accounts_pkey PRIMARY KEY (id);


--
-- Name: eth_coin_circulation eth_coin_circulation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_coin_circulation
    ADD CONSTRAINT eth_coin_circulation_pkey PRIMARY KEY ("timestamp", contract_address);


--
-- Name: exchange_addresses exchange_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_addresses
    ADD CONSTRAINT exchange_addresses_pkey PRIMARY KEY (id);


--
-- Name: featured_items featured_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_pkey PRIMARY KEY (id);


--
-- Name: github_organizations github_organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_organizations
    ADD CONSTRAINT github_organizations_pkey PRIMARY KEY (id);


--
-- Name: ico_currencies ico_currencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ico_currencies
    ADD CONSTRAINT ico_currencies_pkey PRIMARY KEY (id);


--
-- Name: icos icos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.icos
    ADD CONSTRAINT icos_pkey PRIMARY KEY (id);


--
-- Name: infrastructures infrastructures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructures
    ADD CONSTRAINT infrastructures_pkey PRIMARY KEY (id);


--
-- Name: latest_btc_wallet_data latest_btc_wallet_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.latest_btc_wallet_data
    ADD CONSTRAINT latest_btc_wallet_data_pkey PRIMARY KEY (id);


--
-- Name: latest_coinmarketcap_data latest_coinmarketcap_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.latest_coinmarketcap_data
    ADD CONSTRAINT latest_coinmarketcap_data_pkey PRIMARY KEY (id);


--
-- Name: list_items list_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT list_items_pkey PRIMARY KEY (user_list_id, project_id);


--
-- Name: market_segments market_segments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_segments
    ADD CONSTRAINT market_segments_pkey PRIMARY KEY (id);


--
-- Name: notification notification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_pkey PRIMARY KEY (id);


--
-- Name: notification_type notification_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_type
    ADD CONSTRAINT notification_type_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: plans plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (id);


--
-- Name: polls polls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.polls
    ADD CONSTRAINT polls_pkey PRIMARY KEY (id);


--
-- Name: post_images post_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_images
    ADD CONSTRAINT post_images_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: posts_projects posts_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_projects
    ADD CONSTRAINT posts_projects_pkey PRIMARY KEY (id);


--
-- Name: posts_tags posts_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_tags
    ADD CONSTRAINT posts_tags_pkey PRIMARY KEY (id);


--
-- Name: processed_github_archives processed_github_archives_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_github_archives
    ADD CONSTRAINT processed_github_archives_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: project_btc_address project_btc_address_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_btc_address
    ADD CONSTRAINT project_btc_address_pkey PRIMARY KEY (id);


--
-- Name: project_eth_address project_eth_address_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_eth_address
    ADD CONSTRAINT project_eth_address_pkey PRIMARY KEY (id);


--
-- Name: project_market_segments project_market_segments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_market_segments
    ADD CONSTRAINT project_market_segments_pkey PRIMARY KEY (id);


--
-- Name: project project_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT project_pkey PRIMARY KEY (id);


--
-- Name: project_social_volume_query project_social_volume_query_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_social_volume_query
    ADD CONSTRAINT project_social_volume_query_pkey PRIMARY KEY (id);


--
-- Name: project_transparency_statuses project_transparency_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_transparency_statuses
    ADD CONSTRAINT project_transparency_statuses_pkey PRIMARY KEY (id);


--
-- Name: schedule_rescrape_prices schedule_rescrape_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_rescrape_prices
    ADD CONSTRAINT schedule_rescrape_prices_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: signals_historical_activity signals_historical_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signals_historical_activity
    ADD CONSTRAINT signals_historical_activity_pkey PRIMARY KEY (id);


--
-- Name: source_slug_mappings source_slug_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_slug_mappings
    ADD CONSTRAINT source_slug_mappings_pkey PRIMARY KEY (id);


--
-- Name: stripe_events stripe_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stripe_events
    ADD CONSTRAINT stripe_events_pkey PRIMARY KEY (event_id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: telegram_user_tokens telegram_user_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telegram_user_tokens
    ADD CONSTRAINT telegram_user_tokens_pkey PRIMARY KEY (user_id, token);


--
-- Name: timeline_events timeline_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events
    ADD CONSTRAINT timeline_events_pkey PRIMARY KEY (id);


--
-- Name: user_api_key_tokens user_api_key_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_api_key_tokens
    ADD CONSTRAINT user_api_key_tokens_pkey PRIMARY KEY (id);


--
-- Name: user_followers user_followers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_followers
    ADD CONSTRAINT user_followers_pkey PRIMARY KEY (user_id, follower_id);


--
-- Name: user_lists user_lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lists
    ADD CONSTRAINT user_lists_pkey PRIMARY KEY (id);


--
-- Name: user_settings user_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_settings
    ADD CONSTRAINT user_settings_pkey PRIMARY KEY (id);


--
-- Name: user_triggers user_triggers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_triggers
    ADD CONSTRAINT user_triggers_pkey PRIMARY KEY (id);


--
-- Name: user_triggers_tags user_triggers_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_triggers_tags
    ADD CONSTRAINT user_triggers_tags_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: votes votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_pkey PRIMARY KEY (id);


--
-- Name: watchlist_settings watchlist_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watchlist_settings
    ADD CONSTRAINT watchlist_settings_pkey PRIMARY KEY (user_id, watchlist_id);


--
-- Name: currencies_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX currencies_code_index ON public.currencies USING btree (code);


--
-- Name: eth_accounts_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX eth_accounts_address_index ON public.eth_accounts USING btree (address);


--
-- Name: exchange_addresses_address_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX exchange_addresses_address_idx ON public.exchange_addresses USING btree (address);


--
-- Name: featured_items_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX featured_items_post_id_index ON public.featured_items USING btree (post_id);


--
-- Name: featured_items_user_list_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX featured_items_user_list_id_index ON public.featured_items USING btree (user_list_id);


--
-- Name: featured_items_user_trigger_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX featured_items_user_trigger_id_index ON public.featured_items USING btree (user_trigger_id);


--
-- Name: github_organizations_project_id_organization_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX github_organizations_project_id_organization_index ON public.github_organizations USING btree (project_id, organization);


--
-- Name: ico_currencies_currency_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ico_currencies_currency_id_index ON public.ico_currencies USING btree (currency_id);


--
-- Name: ico_currencies_ico_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ico_currencies_ico_id_index ON public.ico_currencies USING btree (ico_id);


--
-- Name: ico_currencies_uk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ico_currencies_uk ON public.ico_currencies USING btree (ico_id, currency_id);


--
-- Name: infrastructures_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX infrastructures_code_index ON public.infrastructures USING btree (code);


--
-- Name: latest_btc_wallet_data_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX latest_btc_wallet_data_address_index ON public.latest_btc_wallet_data USING btree (address);


--
-- Name: latest_coinmarketcap_data_coinmarketcap_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX latest_coinmarketcap_data_coinmarketcap_id_index ON public.latest_coinmarketcap_data USING btree (coinmarketcap_id);


--
-- Name: market_segments_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX market_segments_name_index ON public.market_segments USING btree (name);


--
-- Name: notification_project_id_type_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_project_id_type_id_index ON public.notification USING btree (project_id, type_id);


--
-- Name: notification_type_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX notification_type_name_index ON public.notification_type USING btree (name);


--
-- Name: notifications_project_id_type_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_project_id_type_id_index ON public.notifications USING btree (project_id, type_id);


--
-- Name: one_mapping_per_source; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_mapping_per_source ON public.source_slug_mappings USING btree (source, project_id);


--
-- Name: plans_stripe_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX plans_stripe_id_index ON public.plans USING btree (stripe_id);


--
-- Name: polls_start_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX polls_start_at_index ON public.polls USING btree (start_at);


--
-- Name: post_images_image_url_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX post_images_image_url_index ON public.post_images USING btree (image_url);


--
-- Name: posts_projects_post_id_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX posts_projects_post_id_project_id_index ON public.posts_projects USING btree (post_id, project_id);


--
-- Name: posts_tags_post_id_tag_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX posts_tags_post_id_tag_id_index ON public.posts_tags USING btree (post_id, tag_id);


--
-- Name: processed_github_archives_project_id_archive_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX processed_github_archives_project_id_archive_index ON public.processed_github_archives USING btree (project_id, archive);


--
-- Name: products_stripe_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX products_stripe_id_index ON public.products USING btree (stripe_id);


--
-- Name: project_btc_address_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_btc_address_address_index ON public.project_btc_address USING btree (address);


--
-- Name: project_btc_address_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_btc_address_project_id_index ON public.project_btc_address USING btree (project_id);


--
-- Name: project_coinmarketcap_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_coinmarketcap_id_index ON public.project USING btree (coinmarketcap_id);


--
-- Name: project_eth_address_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_eth_address_address_index ON public.project_eth_address USING btree (address);


--
-- Name: project_eth_address_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_eth_address_project_id_index ON public.project_eth_address USING btree (project_id);


--
-- Name: project_infrastructure_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_infrastructure_id_index ON public.project USING btree (infrastructure_id);


--
-- Name: project_market_segment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_market_segment_id_index ON public.project USING btree (market_segment_id);


--
-- Name: project_market_segments_project_id_market_segment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_market_segments_project_id_market_segment_id_index ON public.project_market_segments USING btree (project_id, market_segment_id);


--
-- Name: project_project_transparency_status_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_project_transparency_status_id_index ON public.project USING btree (project_transparency_status_id);


--
-- Name: project_social_volume_query_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_social_volume_query_project_id_index ON public.project_social_volume_query USING btree (project_id);


--
-- Name: project_transparency_statuses_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_transparency_statuses_name_index ON public.project_transparency_statuses USING btree (name);


--
-- Name: schedule_rescrape_prices_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX schedule_rescrape_prices_project_id_index ON public.schedule_rescrape_prices USING btree (project_id);


--
-- Name: signals_historical_activity_user_id_triggered_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX signals_historical_activity_user_id_triggered_at_index ON public.signals_historical_activity USING btree (user_id, triggered_at);


--
-- Name: source_slug_unique_combination; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX source_slug_unique_combination ON public.source_slug_mappings USING btree (source, slug);


--
-- Name: subscriptions_stripe_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX subscriptions_stripe_id_index ON public.subscriptions USING btree (stripe_id);


--
-- Name: tags_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tags_name_index ON public.tags USING btree (name);


--
-- Name: telegram_user_tokens_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX telegram_user_tokens_token_index ON public.telegram_user_tokens USING btree (token);


--
-- Name: telegram_user_tokens_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX telegram_user_tokens_user_id_index ON public.telegram_user_tokens USING btree (user_id);


--
-- Name: timeline_events_user_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX timeline_events_user_id_inserted_at_index ON public.timeline_events USING btree (user_id, inserted_at);


--
-- Name: user_api_key_tokens_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_api_key_tokens_token_index ON public.user_api_key_tokens USING btree (token);


--
-- Name: user_followers_user_id_follower_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_followers_user_id_follower_id_index ON public.user_followers USING btree (user_id, follower_id);


--
-- Name: user_lists_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_lists_slug_index ON public.user_lists USING btree (slug);


--
-- Name: user_settings_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_settings_user_id_index ON public.user_settings USING btree (user_id);


--
-- Name: user_triggers_tags_user_trigger_id_tag_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_triggers_tags_user_trigger_id_tag_id_index ON public.user_triggers_tags USING btree (user_trigger_id, tag_id);


--
-- Name: user_triggers_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_triggers_user_id_index ON public.user_triggers USING btree (user_id);


--
-- Name: users_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_index ON public.users USING btree (email);


--
-- Name: users_email_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_token_index ON public.users USING btree (email_token);


--
-- Name: users_stripe_customer_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_stripe_customer_id_index ON public.users USING btree (stripe_customer_id);


--
-- Name: users_username_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_username_index ON public.users USING btree (username);


--
-- Name: votes_post_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_post_id_user_id_index ON public.votes USING btree (post_id, user_id);


--
-- Name: eth_accounts eth_accounts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_accounts
    ADD CONSTRAINT eth_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: exchange_addresses exchange_addresses_infrastructure_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_addresses
    ADD CONSTRAINT exchange_addresses_infrastructure_id_fkey FOREIGN KEY (infrastructure_id) REFERENCES public.infrastructures(id);


--
-- Name: featured_items featured_items_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id);


--
-- Name: featured_items featured_items_user_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_user_list_id_fkey FOREIGN KEY (user_list_id) REFERENCES public.user_lists(id);


--
-- Name: featured_items featured_items_user_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_user_trigger_id_fkey FOREIGN KEY (user_trigger_id) REFERENCES public.user_triggers(id);


--
-- Name: github_organizations github_organizations_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_organizations
    ADD CONSTRAINT github_organizations_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: ico_currencies ico_currencies_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ico_currencies
    ADD CONSTRAINT ico_currencies_currency_id_fkey FOREIGN KEY (currency_id) REFERENCES public.currencies(id) ON DELETE CASCADE;


--
-- Name: ico_currencies ico_currencies_ico_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ico_currencies
    ADD CONSTRAINT ico_currencies_ico_id_fkey FOREIGN KEY (ico_id) REFERENCES public.icos(id) ON DELETE CASCADE;


--
-- Name: icos icos_cap_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.icos
    ADD CONSTRAINT icos_cap_currency_id_fkey FOREIGN KEY (cap_currency_id) REFERENCES public.currencies(id);


--
-- Name: icos icos_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.icos
    ADD CONSTRAINT icos_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: list_items list_items_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT list_items_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: list_items list_items_user_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT list_items_user_list_id_fkey FOREIGN KEY (user_list_id) REFERENCES public.user_lists(id) ON DELETE CASCADE;


--
-- Name: notification notification_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: notification notification_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification
    ADD CONSTRAINT notification_type_id_fkey FOREIGN KEY (type_id) REFERENCES public.notification_type(id);


--
-- Name: notifications notifications_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: notifications notifications_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_type_id_fkey FOREIGN KEY (type_id) REFERENCES public.notification_type(id);


--
-- Name: plans plans_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: post_images post_images_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_images
    ADD CONSTRAINT post_images_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: posts posts_poll_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_poll_id_fkey FOREIGN KEY (poll_id) REFERENCES public.polls(id) ON DELETE CASCADE;


--
-- Name: posts_projects posts_projects_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_projects
    ADD CONSTRAINT posts_projects_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id);


--
-- Name: posts_projects posts_projects_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_projects
    ADD CONSTRAINT posts_projects_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: posts_tags posts_tags_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_tags
    ADD CONSTRAINT posts_tags_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id);


--
-- Name: posts_tags posts_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_tags
    ADD CONSTRAINT posts_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id);


--
-- Name: posts posts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: processed_github_archives processed_github_archives_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_github_archives
    ADD CONSTRAINT processed_github_archives_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: project_btc_address project_btc_address_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_btc_address
    ADD CONSTRAINT project_btc_address_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: project_eth_address project_eth_address_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_eth_address
    ADD CONSTRAINT project_eth_address_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: project project_infrastructure_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT project_infrastructure_id_fkey FOREIGN KEY (infrastructure_id) REFERENCES public.infrastructures(id);


--
-- Name: project project_market_segment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT project_market_segment_id_fkey FOREIGN KEY (market_segment_id) REFERENCES public.market_segments(id);


--
-- Name: project_market_segments project_market_segments_market_segment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_market_segments
    ADD CONSTRAINT project_market_segments_market_segment_id_fkey FOREIGN KEY (market_segment_id) REFERENCES public.market_segments(id);


--
-- Name: project_market_segments project_market_segments_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_market_segments
    ADD CONSTRAINT project_market_segments_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: project project_project_transparency_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT project_project_transparency_status_id_fkey FOREIGN KEY (project_transparency_status_id) REFERENCES public.project_transparency_statuses(id);


--
-- Name: project_social_volume_query project_social_volume_query_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_social_volume_query
    ADD CONSTRAINT project_social_volume_query_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: schedule_rescrape_prices schedule_rescrape_prices_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_rescrape_prices
    ADD CONSTRAINT schedule_rescrape_prices_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: signals_historical_activity signals_historical_activity_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signals_historical_activity
    ADD CONSTRAINT signals_historical_activity_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: signals_historical_activity signals_historical_activity_user_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signals_historical_activity
    ADD CONSTRAINT signals_historical_activity_user_trigger_id_fkey FOREIGN KEY (user_trigger_id) REFERENCES public.user_triggers(id);


--
-- Name: source_slug_mappings source_slug_mappings_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_slug_mappings
    ADD CONSTRAINT source_slug_mappings_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.plans(id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: telegram_user_tokens telegram_user_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telegram_user_tokens
    ADD CONSTRAINT telegram_user_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: timeline_events timeline_events_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events
    ADD CONSTRAINT timeline_events_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id);


--
-- Name: timeline_events timeline_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events
    ADD CONSTRAINT timeline_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: timeline_events timeline_events_user_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events
    ADD CONSTRAINT timeline_events_user_list_id_fkey FOREIGN KEY (user_list_id) REFERENCES public.user_lists(id);


--
-- Name: timeline_events timeline_events_user_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events
    ADD CONSTRAINT timeline_events_user_trigger_id_fkey FOREIGN KEY (user_trigger_id) REFERENCES public.user_triggers(id);


--
-- Name: user_api_key_tokens user_api_key_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_api_key_tokens
    ADD CONSTRAINT user_api_key_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_followers user_followers_follower_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_followers
    ADD CONSTRAINT user_followers_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES public.users(id);


--
-- Name: user_followers user_followers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_followers
    ADD CONSTRAINT user_followers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_lists user_lists_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lists
    ADD CONSTRAINT user_lists_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_settings user_settings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_settings
    ADD CONSTRAINT user_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_triggers_tags user_triggers_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_triggers_tags
    ADD CONSTRAINT user_triggers_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id);


--
-- Name: user_triggers_tags user_triggers_tags_user_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_triggers_tags
    ADD CONSTRAINT user_triggers_tags_user_trigger_id_fkey FOREIGN KEY (user_trigger_id) REFERENCES public.user_triggers(id);


--
-- Name: user_triggers user_triggers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_triggers
    ADD CONSTRAINT user_triggers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: votes votes_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: votes votes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: watchlist_settings watchlist_settings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watchlist_settings
    ADD CONSTRAINT watchlist_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: watchlist_settings watchlist_settings_watchlist_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watchlist_settings
    ADD CONSTRAINT watchlist_settings_watchlist_id_fkey FOREIGN KEY (watchlist_id) REFERENCES public.user_lists(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

INSERT INTO public."schema_migrations" (version) VALUES (20171008200815), (20171008203355), (20171008204451), (20171008204756), (20171008205435), (20171008205503), (20171008205547), (20171008210439), (20171017104338), (20171017104607), (20171017104817), (20171017111725), (20171017125741), (20171017132729), (20171018120438), (20171025082707), (20171106052403), (20171114151430), (20171122153530), (20171128130151), (20171128183758), (20171128183804), (20171128222957), (20171129022700), (20171130144543), (20171205103038), (20171212105707), (20171213093912), (20171213104154), (20171213115525), (20171213120408), (20171213121433), (20171213180753), (20171215133550), (20171218112921), (20171219162029), (20171224113921), (20171224114352), (20171225093503), (20171226143530), (20171228163415), (20180102111752), (20180103102329), (20180105091551), (20180108100755), (20180108110118), (20180108140221), (20180112084549), (20180112215750), (20180114093910), (20180114095310), (20180115141540), (20180122122441), (20180126093200), (20180129165526), (20180131140259), (20180202131721), (20180205101949), (20180209121215), (20180211202224), (20180215105804), (20180216182032), (20180219102602), (20180219133328), (20180222135838), (20180223114151), (20180227090003), (20180319041803), (20180322143849), (20180323111505), (20180330045410), (20180411112814), (20180411112855), (20180411113727), (20180411120339), (20180412083038), (20180418141807), (20180423115739), (20180423130032), (20180424122421), (20180424135326), (20180425145127), (20180430093358), (20180503110930), (20180504071348), (20180526114244), (20180601085613), (20180620114029), (20180625122114), (20180628092208), (20180704075131), (20180704075135), (20180708110131), (20180708114337), (20180829153735), (20180830080945), (20180831074008), (20180831094245), (20180903115442), (20180912124703), (20180914114619), (20181002095110), (20181029104029), (20181102114904), (20181107134850), (20181129132524), (20181218142658), (20190110101520), (20190114144216), (20190116105831), (20190124134046), (20190128085100), (20190215131827), (20190225144858), (20190227153610), (20190227153724), (20190312142628), (20190327104558), (20190327105353), (20190328141739), (20190329101433), (20190404143453), (20190404144631), (20190405124751), (20190408081738), (20190412100349), (20190412112500), (20190424135000), (20190510071926), (20190510075046), (20190510080002), (20190513132556), (20190529122938), (20190617065216), (20190621125354), (20190624081130), (20190625083137), (20190626121217), (20190627081358), (20190709125125), (20190710140802), (20190717072702), (20190717135349), (20190717143049), (20190718074943), (20190723113907), (20190724124405), (20190725093848), (20190725094221), (20190725101739), (20190726123417), (20190726123917), (20190730121330), (20190731130643), (20190805111217), (20190806145645), (20190807074910), (20190808100822), (20190808132340), (20190812114357), (20190819140756), (20190820130640), (20190828092907), (20190828104846), (20190828104909), (20190903113410), (20190903145409), (20190904083753), (20190905094949), (20190905135749);

