--
-- PostgreSQL database dump
--

-- Dumped from database version 10.13
-- Dumped by pg_dump version 11.6

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
-- Name: lang; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.lang AS ENUM (
    'en',
    'jp'
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
-- Name: active_widgets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_widgets (
    id bigint NOT NULL,
    title character varying(255) NOT NULL,
    description character varying(255),
    is_active boolean DEFAULT true,
    image_link character varying(255),
    video_link character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: active_widgets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_widgets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_widgets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_widgets_id_seq OWNED BY public.active_widgets.id;


--
-- Name: chart_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chart_configurations (
    id bigint NOT NULL,
    user_id bigint,
    project_id bigint,
    title character varying(255),
    description text,
    is_public boolean DEFAULT false,
    metrics character varying(255)[] DEFAULT ARRAY[]::character varying[],
    anomalies character varying(255)[] DEFAULT ARRAY[]::character varying[],
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    drawings jsonb,
    options jsonb,
    post_id bigint
);


--
-- Name: chart_configurations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.chart_configurations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: chart_configurations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.chart_configurations_id_seq OWNED BY public.chart_configurations.id;


--
-- Name: comment_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comment_notifications (
    id bigint NOT NULL,
    last_insight_comment_id integer,
    last_timeline_event_comment_id integer,
    notify_users_map jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: comment_notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.comment_notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: comment_notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.comment_notifications_id_seq OWNED BY public.comment_notifications.id;


--
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comments (
    id bigint NOT NULL,
    content text NOT NULL,
    subcomments_count integer DEFAULT 0 NOT NULL,
    user_id bigint NOT NULL,
    parent_id bigint,
    root_parent_id bigint,
    edited_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: comments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.comments_id_seq OWNED BY public.comments.id;


--
-- Name: contract_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_addresses (
    id bigint NOT NULL,
    address character varying(255) NOT NULL,
    decimals integer DEFAULT 0,
    label character varying(255),
    description text,
    project_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: contract_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_addresses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_addresses_id_seq OWNED BY public.contract_addresses.id;


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
-- Name: exchange_market_pair_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_market_pair_mappings (
    id bigint NOT NULL,
    exchange character varying(255) NOT NULL,
    market_pair character varying(255) NOT NULL,
    from_ticker character varying(255) NOT NULL,
    to_ticker character varying(255) NOT NULL,
    from_slug character varying(255) NOT NULL,
    to_slug character varying(255) NOT NULL,
    source character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: exchange_market_pair_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.exchange_market_pair_mappings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: exchange_market_pair_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.exchange_market_pair_mappings_id_seq OWNED BY public.exchange_market_pair_mappings.id;


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
    chart_configuration_id bigint,
    table_configuration_id bigint,
    CONSTRAINT only_one_fk CHECK ((((((
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
END) +
CASE
    WHEN (chart_configuration_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (table_configuration_id IS NULL) THEN 0
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
-- Name: kafka_label_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kafka_label_records (
    id bigint NOT NULL,
    topic character varying(255) NOT NULL,
    sign integer NOT NULL,
    address character varying(255) NOT NULL,
    blockchain character varying(255) NOT NULL,
    label character varying(255) NOT NULL,
    metadata character varying(255),
    datetime timestamp without time zone NOT NULL
);


--
-- Name: kafka_label_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.kafka_label_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: kafka_label_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.kafka_label_records_id_seq OWNED BY public.kafka_label_records.id;


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
    logo_updated_at timestamp without time zone,
    coinmarketcap_integer_id integer
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
    name character varying(255) NOT NULL,
    type character varying(255)
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
-- Name: metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_id_seq OWNED BY public.metrics.id;


--
-- Name: newsletter_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.newsletter_tokens (
    id bigint NOT NULL,
    token character varying(255),
    email character varying(255),
    email_token_generated_at timestamp(0) without time zone,
    email_token_validated_at timestamp(0) without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: newsletter_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.newsletter_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: newsletter_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.newsletter_tokens_id_seq OWNED BY public.newsletter_tokens.id;


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
    stripe_id character varying(255),
    is_deprecated boolean DEFAULT false,
    "order" integer DEFAULT 0
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
-- Name: popular_search_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.popular_search_terms (
    id bigint NOT NULL,
    search_term character varying(255) NOT NULL,
    selector_type character varying(255) DEFAULT 'text'::character varying NOT NULL,
    datetime timestamp without time zone,
    title character varying(255) NOT NULL,
    options jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: popular_search_terms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.popular_search_terms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: popular_search_terms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.popular_search_terms_id_seq OWNED BY public.popular_search_terms.id;


--
-- Name: post_comments_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_comments_mapping (
    id bigint NOT NULL,
    comment_id bigint,
    post_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: post_comments_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.post_comments_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: post_comments_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.post_comments_mapping_id_seq OWNED BY public.post_comments_mapping.id;


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
    published_at timestamp without time zone,
    is_pulse boolean DEFAULT false,
    is_paywall_required boolean DEFAULT false,
    metrics character varying(255)[] DEFAULT ARRAY[]::character varying[],
    prediction character varying(255) DEFAULT NULL::character varying,
    price_chart_project_id bigint,
    document_tokens tsvector,
    is_chart_event boolean DEFAULT false,
    chart_event_datetime timestamp(0) without time zone,
    chart_configuration_for_event_id bigint
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
-- Name: posts_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts_metrics (
    id bigint NOT NULL,
    post_id bigint,
    metric_id bigint
);


--
-- Name: posts_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.posts_metrics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: posts_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.posts_metrics_id_seq OWNED BY public.posts_metrics.id;


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
-- Name: price_migration_tmp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_migration_tmp (
    id bigint NOT NULL,
    slug character varying(255) NOT NULL,
    is_migrated boolean DEFAULT false,
    progress text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: price_migration_tmp_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.price_migration_tmp_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: price_migration_tmp_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.price_migration_tmp_id_seq OWNED BY public.price_migration_tmp.id;


--
-- Name: price_scraping_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_scraping_progress (
    id bigint NOT NULL,
    identifier character varying(255) NOT NULL,
    datetime timestamp without time zone NOT NULL,
    source character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: price_scraping_progress_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.price_scraping_progress_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: price_scraping_progress_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.price_scraping_progress_id_seq OWNED BY public.price_scraping_progress.id;


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
    stripe_id character varying(255),
    code character varying(255)
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
    logo_url character varying(255),
    slug character varying(255),
    is_hidden boolean DEFAULT false,
    dark_logo_url character varying(255)
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
    market_segment_id bigint
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
-- Name: promo_coupons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promo_coupons (
    id bigint NOT NULL,
    email character varying(255) NOT NULL,
    message text,
    coupon character varying(255),
    origin_url character varying(255),
    lang public.lang
);


--
-- Name: promo_coupons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.promo_coupons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: promo_coupons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.promo_coupons_id_seq OWNED BY public.promo_coupons.id;


--
-- Name: promo_trials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promo_trials (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    trial_days integer NOT NULL,
    plans character varying(255)[] NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: promo_trials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.promo_trials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: promo_trials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.promo_trials_id_seq OWNED BY public.promo_trials.id;


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reports (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    url character varying(255) NOT NULL,
    is_published boolean DEFAULT false NOT NULL,
    is_pro boolean DEFAULT false NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    tags character varying(255)[] DEFAULT ARRAY[]::character varying[]
);


--
-- Name: reports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reports_id_seq OWNED BY public.reports.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id bigint NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


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
-- Name: short_urls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.short_urls (
    id bigint NOT NULL,
    short_url character varying(255) NOT NULL,
    full_url text NOT NULL,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: short_urls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.short_urls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: short_urls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.short_urls_id_seq OWNED BY public.short_urls.id;


--
-- Name: sign_up_trials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sign_up_trials (
    id bigint NOT NULL,
    user_id bigint,
    sent_welcome_email boolean DEFAULT false,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    sent_trial_will_end_email boolean DEFAULT false,
    subscription_id bigint,
    sent_first_education_email boolean DEFAULT false,
    sent_second_education_email boolean DEFAULT false,
    sent_cc_will_be_charged boolean DEFAULT false,
    sent_trial_finished_without_cc boolean DEFAULT false,
    is_finished boolean DEFAULT false
);


--
-- Name: sign_up_trials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sign_up_trials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sign_up_trials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sign_up_trials_id_seq OWNED BY public.sign_up_trials.id;


--
-- Name: signals_historical_activity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.signals_historical_activity (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    user_trigger_id bigint NOT NULL,
    payload jsonb,
    triggered_at timestamp without time zone NOT NULL,
    data jsonb
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
    status public.status DEFAULT 'initial'::public.status NOT NULL,
    trial_end timestamp without time zone,
    inserted_at timestamp without time zone,
    updated_at timestamp without time zone
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
-- Name: table_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.table_configurations (
    id bigint NOT NULL,
    user_id bigint,
    title character varying(255) NOT NULL,
    description text,
    is_public boolean DEFAULT false NOT NULL,
    page_size integer DEFAULT 50,
    columns jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: table_configurations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.table_configurations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: table_configurations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.table_configurations_id_seq OWNED BY public.table_configurations.id;


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
-- Name: timeline_event_comments_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.timeline_event_comments_mapping (
    id bigint NOT NULL,
    comment_id bigint,
    timeline_event_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: timeline_event_comments_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.timeline_event_comments_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: timeline_event_comments_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.timeline_event_comments_mapping_id_seq OWNED BY public.timeline_event_comments_mapping.id;


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
    payload jsonb,
    data jsonb,
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
-- Name: user_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_events (
    id bigint NOT NULL,
    event_name character varying(255) NOT NULL,
    created_at timestamp(0) without time zone NOT NULL,
    metadata jsonb,
    remote_id character varying(255),
    user_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: user_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_events_id_seq OWNED BY public.user_events.id;


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
-- Name: user_intercom_attributes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_intercom_attributes (
    id bigint NOT NULL,
    properties jsonb,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: user_intercom_attributes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_intercom_attributes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_intercom_attributes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_intercom_attributes_id_seq OWNED BY public.user_intercom_attributes.id;


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
    slug character varying(255),
    is_monitored boolean DEFAULT false,
    table_configuration_id bigint,
    description text
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
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    user_id bigint NOT NULL,
    role_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


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
    stripe_customer_id character varying(255),
    avatar_url character varying(255),
    is_registered boolean DEFAULT false
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
    post_id bigint,
    user_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    timeline_event_id bigint,
    count integer DEFAULT 1,
    CONSTRAINT only_one_fk CHECK (((
CASE
    WHEN (post_id IS NULL) THEN 0
    ELSE 1
END +
CASE
    WHEN (timeline_event_id IS NULL) THEN 0
    ELSE 1
END) = 1))
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
-- Name: active_widgets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_widgets ALTER COLUMN id SET DEFAULT nextval('public.active_widgets_id_seq'::regclass);


--
-- Name: chart_configurations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configurations ALTER COLUMN id SET DEFAULT nextval('public.chart_configurations_id_seq'::regclass);


--
-- Name: comment_notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_notifications ALTER COLUMN id SET DEFAULT nextval('public.comment_notifications_id_seq'::regclass);


--
-- Name: comments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments ALTER COLUMN id SET DEFAULT nextval('public.comments_id_seq'::regclass);


--
-- Name: contract_addresses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_addresses ALTER COLUMN id SET DEFAULT nextval('public.contract_addresses_id_seq'::regclass);


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
-- Name: exchange_market_pair_mappings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_market_pair_mappings ALTER COLUMN id SET DEFAULT nextval('public.exchange_market_pair_mappings_id_seq'::regclass);


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
-- Name: kafka_label_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kafka_label_records ALTER COLUMN id SET DEFAULT nextval('public.kafka_label_records_id_seq'::regclass);


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
-- Name: metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics ALTER COLUMN id SET DEFAULT nextval('public.metrics_id_seq'::regclass);


--
-- Name: newsletter_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.newsletter_tokens ALTER COLUMN id SET DEFAULT nextval('public.newsletter_tokens_id_seq'::regclass);


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
-- Name: popular_search_terms id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.popular_search_terms ALTER COLUMN id SET DEFAULT nextval('public.popular_search_terms_id_seq'::regclass);


--
-- Name: post_comments_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments_mapping ALTER COLUMN id SET DEFAULT nextval('public.post_comments_mapping_id_seq'::regclass);


--
-- Name: post_images id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_images ALTER COLUMN id SET DEFAULT nextval('public.post_images_id_seq'::regclass);


--
-- Name: posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts ALTER COLUMN id SET DEFAULT nextval('public.posts_id_seq'::regclass);


--
-- Name: posts_metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_metrics ALTER COLUMN id SET DEFAULT nextval('public.posts_metrics_id_seq'::regclass);


--
-- Name: posts_projects id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_projects ALTER COLUMN id SET DEFAULT nextval('public.posts_projects_id_seq'::regclass);


--
-- Name: posts_tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_tags ALTER COLUMN id SET DEFAULT nextval('public.posts_tags_id_seq'::regclass);


--
-- Name: price_migration_tmp id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_migration_tmp ALTER COLUMN id SET DEFAULT nextval('public.price_migration_tmp_id_seq'::regclass);


--
-- Name: price_scraping_progress id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_scraping_progress ALTER COLUMN id SET DEFAULT nextval('public.price_scraping_progress_id_seq'::regclass);


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
-- Name: promo_coupons id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_coupons ALTER COLUMN id SET DEFAULT nextval('public.promo_coupons_id_seq'::regclass);


--
-- Name: promo_trials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_trials ALTER COLUMN id SET DEFAULT nextval('public.promo_trials_id_seq'::regclass);


--
-- Name: reports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports ALTER COLUMN id SET DEFAULT nextval('public.reports_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: schedule_rescrape_prices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_rescrape_prices ALTER COLUMN id SET DEFAULT nextval('public.schedule_rescrape_prices_id_seq'::regclass);


--
-- Name: short_urls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.short_urls ALTER COLUMN id SET DEFAULT nextval('public.short_urls_id_seq'::regclass);


--
-- Name: sign_up_trials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sign_up_trials ALTER COLUMN id SET DEFAULT nextval('public.sign_up_trials_id_seq'::regclass);


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
-- Name: table_configurations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.table_configurations ALTER COLUMN id SET DEFAULT nextval('public.table_configurations_id_seq'::regclass);


--
-- Name: tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags ALTER COLUMN id SET DEFAULT nextval('public.tags_id_seq'::regclass);


--
-- Name: timeline_event_comments_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_event_comments_mapping ALTER COLUMN id SET DEFAULT nextval('public.timeline_event_comments_mapping_id_seq'::regclass);


--
-- Name: timeline_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events ALTER COLUMN id SET DEFAULT nextval('public.timeline_events_id_seq'::regclass);


--
-- Name: user_api_key_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_api_key_tokens ALTER COLUMN id SET DEFAULT nextval('public.user_api_key_tokens_id_seq'::regclass);


--
-- Name: user_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_events ALTER COLUMN id SET DEFAULT nextval('public.user_events_id_seq'::regclass);


--
-- Name: user_intercom_attributes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_intercom_attributes ALTER COLUMN id SET DEFAULT nextval('public.user_intercom_attributes_id_seq'::regclass);


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
-- Name: active_widgets active_widgets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_widgets
    ADD CONSTRAINT active_widgets_pkey PRIMARY KEY (id);


--
-- Name: chart_configurations chart_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configurations
    ADD CONSTRAINT chart_configurations_pkey PRIMARY KEY (id);


--
-- Name: comment_notifications comment_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_notifications
    ADD CONSTRAINT comment_notifications_pkey PRIMARY KEY (id);


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- Name: contract_addresses contract_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_addresses
    ADD CONSTRAINT contract_addresses_pkey PRIMARY KEY (id);


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
-- Name: exchange_market_pair_mappings exchange_market_pair_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_market_pair_mappings
    ADD CONSTRAINT exchange_market_pair_mappings_pkey PRIMARY KEY (id);


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
-- Name: kafka_label_records kafka_label_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kafka_label_records
    ADD CONSTRAINT kafka_label_records_pkey PRIMARY KEY (id);


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
-- Name: metrics metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics
    ADD CONSTRAINT metrics_pkey PRIMARY KEY (id);


--
-- Name: newsletter_tokens newsletter_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.newsletter_tokens
    ADD CONSTRAINT newsletter_tokens_pkey PRIMARY KEY (id);


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
-- Name: popular_search_terms popular_search_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.popular_search_terms
    ADD CONSTRAINT popular_search_terms_pkey PRIMARY KEY (id);


--
-- Name: post_comments_mapping post_comments_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments_mapping
    ADD CONSTRAINT post_comments_mapping_pkey PRIMARY KEY (id);


--
-- Name: post_images post_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_images
    ADD CONSTRAINT post_images_pkey PRIMARY KEY (id);


--
-- Name: posts_metrics posts_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_metrics
    ADD CONSTRAINT posts_metrics_pkey PRIMARY KEY (id);


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
-- Name: price_migration_tmp price_migration_tmp_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_migration_tmp
    ADD CONSTRAINT price_migration_tmp_pkey PRIMARY KEY (id);


--
-- Name: price_scraping_progress price_scraping_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_scraping_progress
    ADD CONSTRAINT price_scraping_progress_pkey PRIMARY KEY (id);


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
-- Name: promo_coupons promo_coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_coupons
    ADD CONSTRAINT promo_coupons_pkey PRIMARY KEY (id);


--
-- Name: promo_trials promo_trials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_trials
    ADD CONSTRAINT promo_trials_pkey PRIMARY KEY (id);


--
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


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
-- Name: short_urls short_urls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.short_urls
    ADD CONSTRAINT short_urls_pkey PRIMARY KEY (id);


--
-- Name: sign_up_trials sign_up_trials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sign_up_trials
    ADD CONSTRAINT sign_up_trials_pkey PRIMARY KEY (id);


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
-- Name: table_configurations table_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.table_configurations
    ADD CONSTRAINT table_configurations_pkey PRIMARY KEY (id);


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
-- Name: timeline_event_comments_mapping timeline_event_comments_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_event_comments_mapping
    ADD CONSTRAINT timeline_event_comments_mapping_pkey PRIMARY KEY (id);


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
-- Name: user_events user_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_events
    ADD CONSTRAINT user_events_pkey PRIMARY KEY (id);


--
-- Name: user_followers user_followers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_followers
    ADD CONSTRAINT user_followers_pkey PRIMARY KEY (user_id, follower_id);


--
-- Name: user_intercom_attributes user_intercom_attributes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_intercom_attributes
    ADD CONSTRAINT user_intercom_attributes_pkey PRIMARY KEY (id);


--
-- Name: user_lists user_lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lists
    ADD CONSTRAINT user_lists_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);


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
-- Name: chart_configurations_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chart_configurations_project_id_index ON public.chart_configurations USING btree (project_id);


--
-- Name: chart_configurations_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chart_configurations_user_id_index ON public.chart_configurations USING btree (user_id);


--
-- Name: contract_addresses_project_id_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contract_addresses_project_id_address_index ON public.contract_addresses USING btree (project_id, address);


--
-- Name: currencies_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX currencies_code_index ON public.currencies USING btree (code);


--
-- Name: document_tokens_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_tokens_index ON public.posts USING gin (document_tokens);


--
-- Name: email_token_uk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX email_token_uk ON public.newsletter_tokens USING btree (email, token);


--
-- Name: eth_accounts_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX eth_accounts_address_index ON public.eth_accounts USING btree (address);


--
-- Name: exchange_addresses_address_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX exchange_addresses_address_idx ON public.exchange_addresses USING btree (address);


--
-- Name: exchange_market_pair_mappings_exchange_source_market_pair_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX exchange_market_pair_mappings_exchange_source_market_pair_index ON public.exchange_market_pair_mappings USING btree (exchange, source, market_pair);


--
-- Name: featured_items_chart_configuration_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX featured_items_chart_configuration_id_index ON public.featured_items USING btree (chart_configuration_id);


--
-- Name: featured_items_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX featured_items_post_id_index ON public.featured_items USING btree (post_id);


--
-- Name: featured_items_table_configuration_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX featured_items_table_configuration_id_index ON public.featured_items USING btree (table_configuration_id);


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
-- Name: metrics_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX metrics_name_index ON public.metrics USING btree (name);


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
-- Name: post_comments_mapping_comment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX post_comments_mapping_comment_id_index ON public.post_comments_mapping USING btree (comment_id);


--
-- Name: post_comments_mapping_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_comments_mapping_post_id_index ON public.post_comments_mapping USING btree (post_id);


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
-- Name: price_scraping_progress_identifier_source_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX price_scraping_progress_identifier_source_index ON public.price_scraping_progress USING btree (identifier, source);


--
-- Name: processed_github_archives_project_id_archive_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX processed_github_archives_project_id_archive_index ON public.processed_github_archives USING btree (project_id, archive);


--
-- Name: products_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX products_code_index ON public.products USING btree (code);


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
-- Name: project_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_slug_index ON public.project USING btree (slug);


--
-- Name: project_social_volume_query_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_social_volume_query_project_id_index ON public.project_social_volume_query USING btree (project_id);


--
-- Name: project_transparency_statuses_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_transparency_statuses_name_index ON public.project_transparency_statuses USING btree (name);


--
-- Name: promo_coupons_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX promo_coupons_email_index ON public.promo_coupons USING btree (email);


--
-- Name: schedule_rescrape_prices_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX schedule_rescrape_prices_project_id_index ON public.schedule_rescrape_prices USING btree (project_id);


--
-- Name: short_urls_short_url_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX short_urls_short_url_index ON public.short_urls USING btree (short_url);


--
-- Name: sign_up_trials_subscription_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sign_up_trials_subscription_id_index ON public.sign_up_trials USING btree (subscription_id);


--
-- Name: sign_up_trials_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sign_up_trials_user_id_index ON public.sign_up_trials USING btree (user_id);


--
-- Name: signals_historical_activity_user_id_triggered_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX signals_historical_activity_user_id_triggered_at_index ON public.signals_historical_activity USING btree (user_id, triggered_at);


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
-- Name: timeline_event_comments_mapping_comment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX timeline_event_comments_mapping_comment_id_index ON public.timeline_event_comments_mapping USING btree (comment_id);


--
-- Name: timeline_event_comments_mapping_timeline_event_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX timeline_event_comments_mapping_timeline_event_id_index ON public.timeline_event_comments_mapping USING btree (timeline_event_id);


--
-- Name: timeline_events_user_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX timeline_events_user_id_inserted_at_index ON public.timeline_events USING btree (user_id, inserted_at);


--
-- Name: user_api_key_tokens_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_api_key_tokens_token_index ON public.user_api_key_tokens USING btree (token);


--
-- Name: user_events_remote_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_events_remote_id_index ON public.user_events USING btree (remote_id);


--
-- Name: user_events_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_events_user_id_index ON public.user_events USING btree (user_id);


--
-- Name: user_followers_user_id_follower_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_followers_user_id_follower_id_index ON public.user_followers USING btree (user_id, follower_id);


--
-- Name: user_intercom_attributes_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_intercom_attributes_user_id_index ON public.user_intercom_attributes USING btree (user_id);


--
-- Name: user_lists_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_lists_slug_index ON public.user_lists USING btree (slug);


--
-- Name: user_roles_user_id_role_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_roles_user_id_role_id_index ON public.user_roles USING btree (user_id, role_id);


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
-- Name: votes_timeline_event_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_timeline_event_id_user_id_index ON public.votes USING btree (timeline_event_id, user_id);


--
-- Name: chart_configurations chart_configurations_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configurations
    ADD CONSTRAINT chart_configurations_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id);


--
-- Name: chart_configurations chart_configurations_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configurations
    ADD CONSTRAINT chart_configurations_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: chart_configurations chart_configurations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configurations
    ADD CONSTRAINT chart_configurations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: comments comments_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: comments comments_root_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_root_parent_id_fkey FOREIGN KEY (root_parent_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: comments comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: contract_addresses contract_addresses_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_addresses
    ADD CONSTRAINT contract_addresses_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id);


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
-- Name: featured_items featured_items_chart_configuration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_chart_configuration_id_fkey FOREIGN KEY (chart_configuration_id) REFERENCES public.chart_configurations(id);


--
-- Name: featured_items featured_items_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id);


--
-- Name: featured_items featured_items_table_configuration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_table_configuration_id_fkey FOREIGN KEY (table_configuration_id) REFERENCES public.table_configurations(id);


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
-- Name: post_comments_mapping post_comments_mapping_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments_mapping
    ADD CONSTRAINT post_comments_mapping_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: post_comments_mapping post_comments_mapping_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments_mapping
    ADD CONSTRAINT post_comments_mapping_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: post_images post_images_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_images
    ADD CONSTRAINT post_images_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: posts posts_chart_configuration_for_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_chart_configuration_for_event_id_fkey FOREIGN KEY (chart_configuration_for_event_id) REFERENCES public.chart_configurations(id);


--
-- Name: posts_metrics posts_metrics_metric_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_metrics
    ADD CONSTRAINT posts_metrics_metric_id_fkey FOREIGN KEY (metric_id) REFERENCES public.metrics(id);


--
-- Name: posts_metrics posts_metrics_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_metrics
    ADD CONSTRAINT posts_metrics_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id);


--
-- Name: posts posts_price_chart_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_price_chart_project_id_fkey FOREIGN KEY (price_chart_project_id) REFERENCES public.project(id);


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
-- Name: promo_trials promo_trials_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_trials
    ADD CONSTRAINT promo_trials_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: schedule_rescrape_prices schedule_rescrape_prices_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_rescrape_prices
    ADD CONSTRAINT schedule_rescrape_prices_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: short_urls short_urls_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.short_urls
    ADD CONSTRAINT short_urls_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: sign_up_trials sign_up_trials_subscription_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sign_up_trials
    ADD CONSTRAINT sign_up_trials_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);


--
-- Name: sign_up_trials sign_up_trials_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sign_up_trials
    ADD CONSTRAINT sign_up_trials_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


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
-- Name: table_configurations table_configurations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.table_configurations
    ADD CONSTRAINT table_configurations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: telegram_user_tokens telegram_user_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telegram_user_tokens
    ADD CONSTRAINT telegram_user_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: timeline_event_comments_mapping timeline_event_comments_mapping_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_event_comments_mapping
    ADD CONSTRAINT timeline_event_comments_mapping_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: timeline_event_comments_mapping timeline_event_comments_mapping_timeline_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_event_comments_mapping
    ADD CONSTRAINT timeline_event_comments_mapping_timeline_event_id_fkey FOREIGN KEY (timeline_event_id) REFERENCES public.timeline_events(id) ON DELETE CASCADE;


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
-- Name: user_events user_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_events
    ADD CONSTRAINT user_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


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
-- Name: user_intercom_attributes user_intercom_attributes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_intercom_attributes
    ADD CONSTRAINT user_intercom_attributes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_lists user_lists_table_configuration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lists
    ADD CONSTRAINT user_lists_table_configuration_id_fkey FOREIGN KEY (table_configuration_id) REFERENCES public.table_configurations(id);


--
-- Name: user_lists user_lists_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lists
    ADD CONSTRAINT user_lists_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


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
-- Name: votes votes_timeline_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_timeline_event_id_fkey FOREIGN KEY (timeline_event_id) REFERENCES public.timeline_events(id) ON DELETE CASCADE;


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

INSERT INTO public."schema_migrations" (version) VALUES (20171008200815);
INSERT INTO public."schema_migrations" (version) VALUES (20171008203355);
INSERT INTO public."schema_migrations" (version) VALUES (20171008204451);
INSERT INTO public."schema_migrations" (version) VALUES (20171008204756);
INSERT INTO public."schema_migrations" (version) VALUES (20171008205435);
INSERT INTO public."schema_migrations" (version) VALUES (20171008205503);
INSERT INTO public."schema_migrations" (version) VALUES (20171008205547);
INSERT INTO public."schema_migrations" (version) VALUES (20171008210439);
INSERT INTO public."schema_migrations" (version) VALUES (20171017104338);
INSERT INTO public."schema_migrations" (version) VALUES (20171017104607);
INSERT INTO public."schema_migrations" (version) VALUES (20171017104817);
INSERT INTO public."schema_migrations" (version) VALUES (20171017111725);
INSERT INTO public."schema_migrations" (version) VALUES (20171017125741);
INSERT INTO public."schema_migrations" (version) VALUES (20171017132729);
INSERT INTO public."schema_migrations" (version) VALUES (20171018120438);
INSERT INTO public."schema_migrations" (version) VALUES (20171025082707);
INSERT INTO public."schema_migrations" (version) VALUES (20171106052403);
INSERT INTO public."schema_migrations" (version) VALUES (20171114151430);
INSERT INTO public."schema_migrations" (version) VALUES (20171122153530);
INSERT INTO public."schema_migrations" (version) VALUES (20171128130151);
INSERT INTO public."schema_migrations" (version) VALUES (20171128183758);
INSERT INTO public."schema_migrations" (version) VALUES (20171128183804);
INSERT INTO public."schema_migrations" (version) VALUES (20171128222957);
INSERT INTO public."schema_migrations" (version) VALUES (20171129022700);
INSERT INTO public."schema_migrations" (version) VALUES (20171130144543);
INSERT INTO public."schema_migrations" (version) VALUES (20171205103038);
INSERT INTO public."schema_migrations" (version) VALUES (20171212105707);
INSERT INTO public."schema_migrations" (version) VALUES (20171213093912);
INSERT INTO public."schema_migrations" (version) VALUES (20171213104154);
INSERT INTO public."schema_migrations" (version) VALUES (20171213115525);
INSERT INTO public."schema_migrations" (version) VALUES (20171213120408);
INSERT INTO public."schema_migrations" (version) VALUES (20171213121433);
INSERT INTO public."schema_migrations" (version) VALUES (20171213180753);
INSERT INTO public."schema_migrations" (version) VALUES (20171215133550);
INSERT INTO public."schema_migrations" (version) VALUES (20171218112921);
INSERT INTO public."schema_migrations" (version) VALUES (20171219162029);
INSERT INTO public."schema_migrations" (version) VALUES (20171224113921);
INSERT INTO public."schema_migrations" (version) VALUES (20171224114352);
INSERT INTO public."schema_migrations" (version) VALUES (20171225093503);
INSERT INTO public."schema_migrations" (version) VALUES (20171226143530);
INSERT INTO public."schema_migrations" (version) VALUES (20171228163415);
INSERT INTO public."schema_migrations" (version) VALUES (20180102111752);
INSERT INTO public."schema_migrations" (version) VALUES (20180103102329);
INSERT INTO public."schema_migrations" (version) VALUES (20180105091551);
INSERT INTO public."schema_migrations" (version) VALUES (20180108100755);
INSERT INTO public."schema_migrations" (version) VALUES (20180108110118);
INSERT INTO public."schema_migrations" (version) VALUES (20180108140221);
INSERT INTO public."schema_migrations" (version) VALUES (20180112084549);
INSERT INTO public."schema_migrations" (version) VALUES (20180112215750);
INSERT INTO public."schema_migrations" (version) VALUES (20180114093910);
INSERT INTO public."schema_migrations" (version) VALUES (20180114095310);
INSERT INTO public."schema_migrations" (version) VALUES (20180115141540);
INSERT INTO public."schema_migrations" (version) VALUES (20180122122441);
INSERT INTO public."schema_migrations" (version) VALUES (20180126093200);
INSERT INTO public."schema_migrations" (version) VALUES (20180129165526);
INSERT INTO public."schema_migrations" (version) VALUES (20180131140259);
INSERT INTO public."schema_migrations" (version) VALUES (20180202131721);
INSERT INTO public."schema_migrations" (version) VALUES (20180205101949);
INSERT INTO public."schema_migrations" (version) VALUES (20180209121215);
INSERT INTO public."schema_migrations" (version) VALUES (20180211202224);
INSERT INTO public."schema_migrations" (version) VALUES (20180215105804);
INSERT INTO public."schema_migrations" (version) VALUES (20180216182032);
INSERT INTO public."schema_migrations" (version) VALUES (20180219102602);
INSERT INTO public."schema_migrations" (version) VALUES (20180219133328);
INSERT INTO public."schema_migrations" (version) VALUES (20180222135838);
INSERT INTO public."schema_migrations" (version) VALUES (20180223114151);
INSERT INTO public."schema_migrations" (version) VALUES (20180227090003);
INSERT INTO public."schema_migrations" (version) VALUES (20180319041803);
INSERT INTO public."schema_migrations" (version) VALUES (20180322143849);
INSERT INTO public."schema_migrations" (version) VALUES (20180323111505);
INSERT INTO public."schema_migrations" (version) VALUES (20180330045410);
INSERT INTO public."schema_migrations" (version) VALUES (20180411112814);
INSERT INTO public."schema_migrations" (version) VALUES (20180411112855);
INSERT INTO public."schema_migrations" (version) VALUES (20180411113727);
INSERT INTO public."schema_migrations" (version) VALUES (20180411120339);
INSERT INTO public."schema_migrations" (version) VALUES (20180412083038);
INSERT INTO public."schema_migrations" (version) VALUES (20180418141807);
INSERT INTO public."schema_migrations" (version) VALUES (20180423115739);
INSERT INTO public."schema_migrations" (version) VALUES (20180423130032);
INSERT INTO public."schema_migrations" (version) VALUES (20180424122421);
INSERT INTO public."schema_migrations" (version) VALUES (20180424135326);
INSERT INTO public."schema_migrations" (version) VALUES (20180425145127);
INSERT INTO public."schema_migrations" (version) VALUES (20180430093358);
INSERT INTO public."schema_migrations" (version) VALUES (20180503110930);
INSERT INTO public."schema_migrations" (version) VALUES (20180504071348);
INSERT INTO public."schema_migrations" (version) VALUES (20180526114244);
INSERT INTO public."schema_migrations" (version) VALUES (20180601085613);
INSERT INTO public."schema_migrations" (version) VALUES (20180620114029);
INSERT INTO public."schema_migrations" (version) VALUES (20180625122114);
INSERT INTO public."schema_migrations" (version) VALUES (20180628092208);
INSERT INTO public."schema_migrations" (version) VALUES (20180704075131);
INSERT INTO public."schema_migrations" (version) VALUES (20180704075135);
INSERT INTO public."schema_migrations" (version) VALUES (20180708110131);
INSERT INTO public."schema_migrations" (version) VALUES (20180708114337);
INSERT INTO public."schema_migrations" (version) VALUES (20180829153735);
INSERT INTO public."schema_migrations" (version) VALUES (20180830080945);
INSERT INTO public."schema_migrations" (version) VALUES (20180831074008);
INSERT INTO public."schema_migrations" (version) VALUES (20180831094245);
INSERT INTO public."schema_migrations" (version) VALUES (20180903115442);
INSERT INTO public."schema_migrations" (version) VALUES (20180912124703);
INSERT INTO public."schema_migrations" (version) VALUES (20180914114619);
INSERT INTO public."schema_migrations" (version) VALUES (20181002095110);
INSERT INTO public."schema_migrations" (version) VALUES (20181029104029);
INSERT INTO public."schema_migrations" (version) VALUES (20181102114904);
INSERT INTO public."schema_migrations" (version) VALUES (20181107134850);
INSERT INTO public."schema_migrations" (version) VALUES (20181129132524);
INSERT INTO public."schema_migrations" (version) VALUES (20181218142658);
INSERT INTO public."schema_migrations" (version) VALUES (20190110101520);
INSERT INTO public."schema_migrations" (version) VALUES (20190114144216);
INSERT INTO public."schema_migrations" (version) VALUES (20190116105831);
INSERT INTO public."schema_migrations" (version) VALUES (20190124134046);
INSERT INTO public."schema_migrations" (version) VALUES (20190128085100);
INSERT INTO public."schema_migrations" (version) VALUES (20190215131827);
INSERT INTO public."schema_migrations" (version) VALUES (20190225144858);
INSERT INTO public."schema_migrations" (version) VALUES (20190227153610);
INSERT INTO public."schema_migrations" (version) VALUES (20190227153724);
INSERT INTO public."schema_migrations" (version) VALUES (20190312142628);
INSERT INTO public."schema_migrations" (version) VALUES (20190327104558);
INSERT INTO public."schema_migrations" (version) VALUES (20190327105353);
INSERT INTO public."schema_migrations" (version) VALUES (20190328141739);
INSERT INTO public."schema_migrations" (version) VALUES (20190329101433);
INSERT INTO public."schema_migrations" (version) VALUES (20190404143453);
INSERT INTO public."schema_migrations" (version) VALUES (20190404144631);
INSERT INTO public."schema_migrations" (version) VALUES (20190405124751);
INSERT INTO public."schema_migrations" (version) VALUES (20190408081738);
INSERT INTO public."schema_migrations" (version) VALUES (20190412100349);
INSERT INTO public."schema_migrations" (version) VALUES (20190412112500);
INSERT INTO public."schema_migrations" (version) VALUES (20190424135000);
INSERT INTO public."schema_migrations" (version) VALUES (20190510071926);
INSERT INTO public."schema_migrations" (version) VALUES (20190510075046);
INSERT INTO public."schema_migrations" (version) VALUES (20190510080002);
INSERT INTO public."schema_migrations" (version) VALUES (20190513132556);
INSERT INTO public."schema_migrations" (version) VALUES (20190529122938);
INSERT INTO public."schema_migrations" (version) VALUES (20190617065216);
INSERT INTO public."schema_migrations" (version) VALUES (20190621125354);
INSERT INTO public."schema_migrations" (version) VALUES (20190624081130);
INSERT INTO public."schema_migrations" (version) VALUES (20190625083137);
INSERT INTO public."schema_migrations" (version) VALUES (20190626121217);
INSERT INTO public."schema_migrations" (version) VALUES (20190627081358);
INSERT INTO public."schema_migrations" (version) VALUES (20190709125125);
INSERT INTO public."schema_migrations" (version) VALUES (20190710140802);
INSERT INTO public."schema_migrations" (version) VALUES (20190717072702);
INSERT INTO public."schema_migrations" (version) VALUES (20190717135349);
INSERT INTO public."schema_migrations" (version) VALUES (20190717143049);
INSERT INTO public."schema_migrations" (version) VALUES (20190718074943);
INSERT INTO public."schema_migrations" (version) VALUES (20190723113907);
INSERT INTO public."schema_migrations" (version) VALUES (20190724124405);
INSERT INTO public."schema_migrations" (version) VALUES (20190725093848);
INSERT INTO public."schema_migrations" (version) VALUES (20190725094221);
INSERT INTO public."schema_migrations" (version) VALUES (20190725101739);
INSERT INTO public."schema_migrations" (version) VALUES (20190726123417);
INSERT INTO public."schema_migrations" (version) VALUES (20190726123917);
INSERT INTO public."schema_migrations" (version) VALUES (20190730121330);
INSERT INTO public."schema_migrations" (version) VALUES (20190731130643);
INSERT INTO public."schema_migrations" (version) VALUES (20190805111217);
INSERT INTO public."schema_migrations" (version) VALUES (20190806145645);
INSERT INTO public."schema_migrations" (version) VALUES (20190807074910);
INSERT INTO public."schema_migrations" (version) VALUES (20190808100822);
INSERT INTO public."schema_migrations" (version) VALUES (20190808132340);
INSERT INTO public."schema_migrations" (version) VALUES (20190812114357);
INSERT INTO public."schema_migrations" (version) VALUES (20190819140756);
INSERT INTO public."schema_migrations" (version) VALUES (20190820130640);
INSERT INTO public."schema_migrations" (version) VALUES (20190828092907);
INSERT INTO public."schema_migrations" (version) VALUES (20190828104846);
INSERT INTO public."schema_migrations" (version) VALUES (20190828104909);
INSERT INTO public."schema_migrations" (version) VALUES (20190903113410);
INSERT INTO public."schema_migrations" (version) VALUES (20190903145409);
INSERT INTO public."schema_migrations" (version) VALUES (20190904083753);
INSERT INTO public."schema_migrations" (version) VALUES (20190905094949);
INSERT INTO public."schema_migrations" (version) VALUES (20190905135749);
INSERT INTO public."schema_migrations" (version) VALUES (20190909113137);
INSERT INTO public."schema_migrations" (version) VALUES (20190913143603);
INSERT INTO public."schema_migrations" (version) VALUES (20190917094005);
INSERT INTO public."schema_migrations" (version) VALUES (20190918091846);
INSERT INTO public."schema_migrations" (version) VALUES (20190918183120);
INSERT INTO public."schema_migrations" (version) VALUES (20190920112346);
INSERT INTO public."schema_migrations" (version) VALUES (20190924060356);
INSERT INTO public."schema_migrations" (version) VALUES (20190924080554);
INSERT INTO public."schema_migrations" (version) VALUES (20190925064207);
INSERT INTO public."schema_migrations" (version) VALUES (20190930150509);
INSERT INTO public."schema_migrations" (version) VALUES (20191001084823);
INSERT INTO public."schema_migrations" (version) VALUES (20191002082331);
INSERT INTO public."schema_migrations" (version) VALUES (20191002102531);
INSERT INTO public."schema_migrations" (version) VALUES (20191017202631);
INSERT INTO public."schema_migrations" (version) VALUES (20191023054309);
INSERT INTO public."schema_migrations" (version) VALUES (20191024145152);
INSERT INTO public."schema_migrations" (version) VALUES (20191025095838);
INSERT INTO public."schema_migrations" (version) VALUES (20191029063113);
INSERT INTO public."schema_migrations" (version) VALUES (20191111151413);
INSERT INTO public."schema_migrations" (version) VALUES (20191112123819);
INSERT INTO public."schema_migrations" (version) VALUES (20191118125110);
INSERT INTO public."schema_migrations" (version) VALUES (20191119123752);
INSERT INTO public."schema_migrations" (version) VALUES (20191121063853);
INSERT INTO public."schema_migrations" (version) VALUES (20191125120729);
INSERT INTO public."schema_migrations" (version) VALUES (20191129145419);
INSERT INTO public."schema_migrations" (version) VALUES (20191202142313);
INSERT INTO public."schema_migrations" (version) VALUES (20191205141013);
INSERT INTO public."schema_migrations" (version) VALUES (20191205141411);
INSERT INTO public."schema_migrations" (version) VALUES (20191209154624);
INSERT INTO public."schema_migrations" (version) VALUES (20191212130812);
INSERT INTO public."schema_migrations" (version) VALUES (20191213141747);
INSERT INTO public."schema_migrations" (version) VALUES (20191218090721);
INSERT INTO public."schema_migrations" (version) VALUES (20191218122743);
INSERT INTO public."schema_migrations" (version) VALUES (20191218145851);
INSERT INTO public."schema_migrations" (version) VALUES (20191220095225);
INSERT INTO public."schema_migrations" (version) VALUES (20200106124357);
INSERT INTO public."schema_migrations" (version) VALUES (20200109094339);
INSERT INTO public."schema_migrations" (version) VALUES (20200110131000);
INSERT INTO public."schema_migrations" (version) VALUES (20200116085403);
INSERT INTO public."schema_migrations" (version) VALUES (20200121094946);
INSERT INTO public."schema_migrations" (version) VALUES (20200130104623);
INSERT INTO public."schema_migrations" (version) VALUES (20200210083533);
INSERT INTO public."schema_migrations" (version) VALUES (20200210084320);
INSERT INTO public."schema_migrations" (version) VALUES (20200211153511);
INSERT INTO public."schema_migrations" (version) VALUES (20200211154147);
INSERT INTO public."schema_migrations" (version) VALUES (20200212090429);
INSERT INTO public."schema_migrations" (version) VALUES (20200213124731);
INSERT INTO public."schema_migrations" (version) VALUES (20200213133314);
INSERT INTO public."schema_migrations" (version) VALUES (20200218075548);
INSERT INTO public."schema_migrations" (version) VALUES (20200218080212);
INSERT INTO public."schema_migrations" (version) VALUES (20200218081027);
INSERT INTO public."schema_migrations" (version) VALUES (20200218081756);
INSERT INTO public."schema_migrations" (version) VALUES (20200218083631);
INSERT INTO public."schema_migrations" (version) VALUES (20200304122654);
INSERT INTO public."schema_migrations" (version) VALUES (20200311142308);
INSERT INTO public."schema_migrations" (version) VALUES (20200312091952);
INSERT INTO public."schema_migrations" (version) VALUES (20200316154107);
INSERT INTO public."schema_migrations" (version) VALUES (20200319161901);
INSERT INTO public."schema_migrations" (version) VALUES (20200406084732);
INSERT INTO public."schema_migrations" (version) VALUES (20200406085205);
INSERT INTO public."schema_migrations" (version) VALUES (20200409053448);
INSERT INTO public."schema_migrations" (version) VALUES (20200421065542);
INSERT INTO public."schema_migrations" (version) VALUES (20200421071844);
INSERT INTO public."schema_migrations" (version) VALUES (20200424074942);
INSERT INTO public."schema_migrations" (version) VALUES (20200424143441);
INSERT INTO public."schema_migrations" (version) VALUES (20200429120144);
INSERT INTO public."schema_migrations" (version) VALUES (20200430110513);
INSERT INTO public."schema_migrations" (version) VALUES (20200507075524);
INSERT INTO public."schema_migrations" (version) VALUES (20200507093029);
INSERT INTO public."schema_migrations" (version) VALUES (20200507093201);
INSERT INTO public."schema_migrations" (version) VALUES (20200507133717);
INSERT INTO public."schema_migrations" (version) VALUES (20200513124741);
INSERT INTO public."schema_migrations" (version) VALUES (20200601122422);
INSERT INTO public."schema_migrations" (version) VALUES (20200601142229);
INSERT INTO public."schema_migrations" (version) VALUES (20200602101130);
INSERT INTO public."schema_migrations" (version) VALUES (20200611093359);
INSERT INTO public."schema_migrations" (version) VALUES (20200618135228);
INSERT INTO public."schema_migrations" (version) VALUES (20200619102126);
INSERT INTO public."schema_migrations" (version) VALUES (20200622084937);
INSERT INTO public."schema_migrations" (version) VALUES (20200622093455);
INSERT INTO public."schema_migrations" (version) VALUES (20200622095648);
INSERT INTO public."schema_migrations" (version) VALUES (20200622132624);
INSERT INTO public."schema_migrations" (version) VALUES (20200706070758);
INSERT INTO public."schema_migrations" (version) VALUES (20200707142725);
INSERT INTO public."schema_migrations" (version) VALUES (20200707155254);
INSERT INTO public."schema_migrations" (version) VALUES (20200716074754);
INSERT INTO public."schema_migrations" (version) VALUES (20200727113432);
INSERT INTO public."schema_migrations" (version) VALUES (20200728103633);
INSERT INTO public."schema_migrations" (version) VALUES (20200728105033);
INSERT INTO public."schema_migrations" (version) VALUES (20200804093238);
INSERT INTO public."schema_migrations" (version) VALUES (20200813141704);
INSERT INTO public."schema_migrations" (version) VALUES (20200826101751);
INSERT INTO public."schema_migrations" (version) VALUES (20200826114101);
INSERT INTO public."schema_migrations" (version) VALUES (20200908092849);
