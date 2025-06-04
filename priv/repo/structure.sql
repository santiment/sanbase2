--
-- PostgreSQL database dump
--

-- Dumped from database version 15.1 (Homebrew)
-- Dumped by pg_dump version 15.1 (Homebrew)

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
-- Name: notification_action_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.notification_action_type AS ENUM (
    'create',
    'update',
    'delete',
    'alert',
    'manual'
);


--
-- Name: notification_channel; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.notification_channel AS ENUM (
    'discord',
    'email',
    'telegram'
);


--
-- Name: notification_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.notification_status AS ENUM (
    'pending',
    'completed',
    'failed'
);


--
-- Name: notification_step; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.notification_step AS ENUM (
    'once',
    'before',
    'after',
    'reminder',
    'detected',
    'resolved'
);


--
-- Name: oban_job_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


--
-- Name: question_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.question_type AS ENUM (
    'single_select',
    'multiple_select',
    'open_text',
    'open_number',
    'boolean'
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


--
-- Name: subscription_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.subscription_type AS ENUM (
    'fiat',
    'liquidity',
    'burning_regular',
    'burning_nft',
    'sanr_points_nft'
);


--
-- Name: table_configuration_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.table_configuration_type AS ENUM (
    'project',
    'blockchain_address'
);


--
-- Name: watchlist_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.watchlist_type AS ENUM (
    'project',
    'blockchain_address'
);


--
-- Name: jsonb_rename_keys(jsonb, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jsonb_rename_keys(jdata jsonb, keys text[]) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  result JSONB;
  len INT;
  newkey TEXT;
  oldkey TEXT;
BEGIN
  len = array_length(keys, 1);

  IF len < 1 OR (len % 2) != 0 THEN
    RAISE EXCEPTION 'The length of keys must be even, such as {old1,new1,old2,new2,...}';
  END IF;

  result = jdata;

  FOR i IN 1..len BY 2 LOOP
    oldkey = keys[i];
    IF (jdata ? oldkey) THEN
      newkey = keys[i+1];
      result = (result - oldkey) || jsonb_build_object(newkey, result->oldkey);
    END IF;
  END LOOP;

  RETURN result;
END;
$$;


--
-- Name: movefinishedobanjobs(character varying, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.movefinishedobanjobs(queue_arg character varying, limit_arg bigint) RETURNS bigint
    LANGUAGE plpgsql
    AS $_$
 DECLARE
   rows_count numeric;
 BEGIN
   WITH finished_job_ids_cte AS (
     SELECT id from oban_jobs
     WHERE queue = $1 AND completed_at IS NOT NULL
     LIMIT $2
   ),
   moved_rows AS (
     DELETE FROM oban_jobs a
     WHERE a.id IN (SELECT id FROM finished_job_ids_cte)
     RETURNING a.queue, a.worker, a.args, a.inserted_at, a.completed_at
   )
   INSERT INTO finished_oban_jobs(queue, worker, args, inserted_at, completed_at)
   SELECT * FROM moved_rows;

   GET DIAGNOSTICS rows_count = ROW_COUNT;
   RETURN rows_count;
 END;
 $_$;


--
-- Name: oban_jobs_notify(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.oban_jobs_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  channel text;
  notice json;
BEGIN
  IF NEW.state = 'available' THEN
    channel = 'public.oban_insert';
    notice = json_build_object('queue', NEW.queue);

    PERFORM pg_notify(channel, notice::text);
  END IF;

  RETURN NULL;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: access_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.access_attempts (
    id bigint NOT NULL,
    user_id bigint,
    ip_address character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: access_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.access_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: access_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.access_attempts_id_seq OWNED BY public.access_attempts.id;


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
-- Name: ai_context; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_context (
    id bigint NOT NULL,
    discord_user character varying(255),
    question text,
    answer text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    guild_id character varying(255),
    guild_name character varying(255),
    channel_id character varying(255),
    channel_name character varying(255),
    elapsed_time double precision,
    tokens_request integer,
    tokens_response integer,
    tokens_total integer,
    error_message text,
    total_cost double precision,
    command character varying(255),
    prompt text,
    user_is_pro boolean DEFAULT false,
    thread_id character varying(255),
    thread_name character varying(255),
    votes jsonb DEFAULT '{}'::jsonb,
    route jsonb DEFAULT '{}'::jsonb,
    function_called character varying(255)
);


--
-- Name: ai_context_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_context_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_context_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_context_id_seq OWNED BY public.ai_context.id;


--
-- Name: ai_gen_code; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_gen_code (
    id bigint NOT NULL,
    question text,
    answer text,
    parent_id bigint,
    program text,
    program_result text,
    discord_user text,
    guild_id text,
    guild_name text,
    channel_id text,
    channel_name text,
    elapsed_time integer,
    changes text,
    is_saved_vs boolean DEFAULT false,
    is_from_vs boolean DEFAULT false,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: ai_gen_code_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_gen_code_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_gen_code_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_gen_code_id_seq OWNED BY public.ai_gen_code.id;


--
-- Name: alpha_naratives_emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alpha_naratives_emails (
    id bigint NOT NULL,
    email character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: alpha_naratives_emails_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.alpha_naratives_emails_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: alpha_naratives_emails_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.alpha_naratives_emails_id_seq OWNED BY public.alpha_naratives_emails.id;


--
-- Name: api_call_limits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_call_limits (
    id bigint NOT NULL,
    user_id bigint,
    remote_ip character varying(255) DEFAULT NULL::character varying,
    has_limits boolean DEFAULT true,
    api_calls_limit_plan character varying(255) DEFAULT 'free'::character varying,
    api_calls jsonb DEFAULT '{}'::jsonb,
    has_limits_no_matter_plan boolean DEFAULT true
);


--
-- Name: api_call_limits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_call_limits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_call_limits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_call_limits_id_seq OWNED BY public.api_call_limits.id;


--
-- Name: asset_exchange_pairs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_exchange_pairs (
    id bigint NOT NULL,
    base_asset character varying(255) NOT NULL,
    quote_asset character varying(255) NOT NULL,
    exchange character varying(255) NOT NULL,
    source character varying(255) NOT NULL,
    last_update timestamp(0) without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: asset_exchange_pairs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.asset_exchange_pairs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: asset_exchange_pairs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.asset_exchange_pairs_id_seq OWNED BY public.asset_exchange_pairs.id;


--
-- Name: available_metrics_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.available_metrics_data (
    id bigint NOT NULL,
    metric character varying(255) NOT NULL,
    available_slugs character varying(255)[],
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: available_metrics_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.available_metrics_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: available_metrics_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.available_metrics_data_id_seq OWNED BY public.available_metrics_data.id;


--
-- Name: blockchain_address_comments_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blockchain_address_comments_mapping (
    id bigint NOT NULL,
    comment_id bigint,
    blockchain_address_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: blockchain_address_comments_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blockchain_address_comments_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blockchain_address_comments_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blockchain_address_comments_mapping_id_seq OWNED BY public.blockchain_address_comments_mapping.id;


--
-- Name: blockchain_address_labels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blockchain_address_labels (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    notes character varying(255)
);


--
-- Name: blockchain_address_labels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blockchain_address_labels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blockchain_address_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blockchain_address_labels_id_seq OWNED BY public.blockchain_address_labels.id;


--
-- Name: blockchain_address_user_pairs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blockchain_address_user_pairs (
    id bigint NOT NULL,
    notes character varying(255),
    user_id bigint,
    blockchain_address_id bigint
);


--
-- Name: blockchain_address_user_pairs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blockchain_address_user_pairs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blockchain_address_user_pairs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blockchain_address_user_pairs_id_seq OWNED BY public.blockchain_address_user_pairs.id;


--
-- Name: blockchain_address_user_pairs_labels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blockchain_address_user_pairs_labels (
    id bigint NOT NULL,
    blockchain_address_user_pair_id bigint,
    label_id bigint
);


--
-- Name: blockchain_address_user_pairs_labels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blockchain_address_user_pairs_labels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blockchain_address_user_pairs_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blockchain_address_user_pairs_labels_id_seq OWNED BY public.blockchain_address_user_pairs_labels.id;


--
-- Name: blockchain_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blockchain_addresses (
    id bigint NOT NULL,
    address character varying(255) NOT NULL,
    infrastructure_id bigint,
    notes text
);


--
-- Name: blockchain_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blockchain_addresses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blockchain_addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blockchain_addresses_id_seq OWNED BY public.blockchain_addresses.id;


--
-- Name: chart_configuration_comments_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chart_configuration_comments_mapping (
    id bigint NOT NULL,
    comment_id bigint,
    chart_configuration_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: chart_configuration_comments_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.chart_configuration_comments_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: chart_configuration_comments_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.chart_configuration_comments_mapping_id_seq OWNED BY public.chart_configuration_comments_mapping.id;


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
    metrics text[] DEFAULT ARRAY[]::text[],
    anomalies character varying(255)[] DEFAULT ARRAY[]::character varying[],
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    drawings jsonb,
    options jsonb,
    post_id bigint,
    queries jsonb,
    metrics_json jsonb DEFAULT '{}'::jsonb,
    is_deleted boolean DEFAULT false,
    is_hidden boolean DEFAULT false
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
-- Name: chat_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_messages (
    id uuid NOT NULL,
    chat_id uuid NOT NULL,
    content text NOT NULL,
    role character varying(255) NOT NULL,
    context jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT valid_role CHECK (((role)::text = ANY ((ARRAY['user'::character varying, 'assistant'::character varying])::text[])))
);


--
-- Name: chats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chats (
    id uuid NOT NULL,
    title character varying(255) NOT NULL,
    user_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    type character varying(255) DEFAULT 'dyor_dashboard'::character varying NOT NULL
);


--
-- Name: clickhouse_query_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clickhouse_query_executions (
    id bigint NOT NULL,
    user_id bigint,
    clickhouse_query_id character varying(255) NOT NULL,
    execution_details jsonb NOT NULL,
    credits_cost integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    query_start_time timestamp(0) without time zone NOT NULL,
    query_end_time timestamp(0) without time zone NOT NULL,
    query_id bigint
);


--
-- Name: clickhouse_query_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clickhouse_query_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clickhouse_query_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clickhouse_query_executions_id_seq OWNED BY public.clickhouse_query_executions.id;


--
-- Name: comment_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comment_notifications (
    id bigint NOT NULL,
    last_insight_comment_id integer,
    last_timeline_event_comment_id integer,
    notify_users_map jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    last_chart_configuration_comment_id integer,
    last_watchlist_comment_id integer
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
    updated_at timestamp without time zone NOT NULL,
    is_deleted boolean DEFAULT false,
    is_hidden boolean DEFAULT false
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
-- Name: cryptocompare_exporter_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cryptocompare_exporter_progress (
    id bigint NOT NULL,
    key character varying(255) NOT NULL,
    queue character varying(255) NOT NULL,
    min_timestamp integer NOT NULL,
    max_timestamp integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: cryptocompare_exporter_progress_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cryptocompare_exporter_progress_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cryptocompare_exporter_progress_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cryptocompare_exporter_progress_id_seq OWNED BY public.cryptocompare_exporter_progress.id;


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
-- Name: dashboard_comments_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_comments_mapping (
    id bigint NOT NULL,
    comment_id bigint,
    dashboard_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: dashboard_comments_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dashboard_comments_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboard_comments_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dashboard_comments_mapping_id_seq OWNED BY public.dashboard_comments_mapping.id;


--
-- Name: dashboard_query_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_query_mappings (
    id uuid NOT NULL,
    dashboard_id bigint,
    query_id bigint,
    settings jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: dashboards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboards (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    is_public boolean DEFAULT false NOT NULL,
    panels jsonb,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    is_deleted boolean DEFAULT false,
    is_hidden boolean DEFAULT false,
    parameters jsonb DEFAULT '{}'::jsonb,
    settings jsonb DEFAULT '{}'::jsonb,
    text_widgets jsonb,
    image_widgets jsonb
);


--
-- Name: dashboards_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboards_cache (
    id bigint NOT NULL,
    dashboard_id bigint,
    panels jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    queries jsonb DEFAULT '{}'::jsonb,
    parameters_override_hash character varying(255) DEFAULT 'none'::character varying NOT NULL
);


--
-- Name: dashboards_cache_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dashboards_cache_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboards_cache_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dashboards_cache_id_seq OWNED BY public.dashboards_cache.id;


--
-- Name: dashboards_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboards_history (
    id bigint NOT NULL,
    dashboard_id bigint,
    user_id bigint,
    panels jsonb,
    name character varying(255),
    description text,
    is_public boolean,
    message text,
    hash text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb
);


--
-- Name: dashboards_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dashboards_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboards_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dashboards_history_id_seq OWNED BY public.dashboards_history.id;


--
-- Name: dashboards_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dashboards_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboards_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dashboards_id_seq OWNED BY public.dashboards.id;


--
-- Name: discord_dashboards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.discord_dashboards (
    id bigint NOT NULL,
    panel_id character varying(255),
    name character varying(255),
    channel character varying(255),
    guild character varying(255),
    user_id bigint,
    dashboard_id bigint,
    pinned boolean DEFAULT false,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    discord_user_id character varying(255),
    discord_user_handle character varying(255),
    discord_message_id character varying(255),
    channel_name character varying(255),
    guild_name character varying(255)
);


--
-- Name: discord_dashboards_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.discord_dashboards_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: discord_dashboards_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.discord_dashboards_id_seq OWNED BY public.discord_dashboards.id;


--
-- Name: ecosystems; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ecosystems (
    id bigint NOT NULL,
    ecosystem character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: ecosystems_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ecosystems_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ecosystems_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ecosystems_id_seq OWNED BY public.ecosystems.id;


--
-- Name: email_login_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_login_attempts (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ip_address character varying(39),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: email_login_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.email_login_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: email_login_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.email_login_attempts_id_seq OWNED BY public.email_login_attempts.id;


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
    dashboard_id bigint,
    query_id bigint,
    CONSTRAINT only_one_fk CHECK ((((((((
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
END) +
CASE
    WHEN (dashboard_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (query_id IS NULL) THEN 0
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
-- Name: finished_oban_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finished_oban_jobs (
    id bigint NOT NULL,
    queue character varying(255),
    worker character varying(255),
    args jsonb,
    inserted_at timestamp(0) without time zone,
    completed_at timestamp(0) without time zone
);


--
-- Name: finished_oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.finished_oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: finished_oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.finished_oban_jobs_id_seq OWNED BY public.finished_oban_jobs.id;


--
-- Name: free_form_json_storage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.free_form_json_storage (
    id bigint NOT NULL,
    key character varying(255),
    value jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: free_form_json_storage_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.free_form_json_storage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: free_form_json_storage_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.free_form_json_storage_id_seq OWNED BY public.free_form_json_storage.id;


--
-- Name: geoip_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geoip_data (
    id bigint NOT NULL,
    ip_address character varying(255) NOT NULL,
    is_vpn boolean NOT NULL,
    country_name character varying(255) NOT NULL,
    country_code character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: geoip_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.geoip_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: geoip_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.geoip_data_id_seq OWNED BY public.geoip_data.id;


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
-- Name: gpt_router; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gpt_router (
    id bigint NOT NULL,
    question text,
    route character varying(255),
    scores jsonb DEFAULT '{}'::jsonb,
    error text,
    elapsed_time integer,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    timeframe integer DEFAULT '-1'::integer,
    sentiment boolean DEFAULT false,
    projects character varying(255)[] DEFAULT ARRAY[]::character varying[]
);


--
-- Name: gpt_router_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gpt_router_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gpt_router_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gpt_router_id_seq OWNED BY public.gpt_router.id;


--
-- Name: guardian_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.guardian_tokens (
    jti character varying(255) NOT NULL,
    typ character varying(255),
    aud character varying(255),
    iss character varying(255),
    sub character varying(255),
    exp bigint,
    jwt text,
    claims jsonb,
    last_exchanged_at timestamp(0) without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


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
-- Name: images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.images (
    id bigint NOT NULL,
    url text NOT NULL,
    name character varying(255) NOT NULL,
    notes text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: images_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.images_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: images_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.images_id_seq OWNED BY public.images.id;


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
-- Name: linked_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.linked_users (
    id bigint NOT NULL,
    primary_user_id bigint NOT NULL,
    secondary_user_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: linked_users_candidates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.linked_users_candidates (
    id bigint NOT NULL,
    primary_user_id bigint NOT NULL,
    secondary_user_id bigint NOT NULL,
    token character varying(255) NOT NULL,
    is_confirmed boolean DEFAULT false NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: linked_users_candidates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.linked_users_candidates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: linked_users_candidates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.linked_users_candidates_id_seq OWNED BY public.linked_users_candidates.id;


--
-- Name: linked_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.linked_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: linked_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.linked_users_id_seq OWNED BY public.linked_users.id;


--
-- Name: list_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_items (
    user_list_id bigint NOT NULL,
    project_id bigint,
    blockchain_address_user_pair_id bigint,
    id integer NOT NULL,
    CONSTRAINT only_one_fk CHECK (((
CASE
    WHEN (blockchain_address_user_pair_id IS NULL) THEN 0
    ELSE 1
END +
CASE
    WHEN (project_id IS NULL) THEN 0
    ELSE 1
END) = 1))
);


--
-- Name: list_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.list_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: list_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.list_items_id_seq OWNED BY public.list_items.id;


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
-- Name: menu_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menu_items (
    id bigint NOT NULL,
    parent_id bigint,
    query_id bigint,
    dashboard_id bigint,
    menu_id bigint,
    "position" integer,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT only_one_fk CHECK ((((
CASE
    WHEN (query_id IS NULL) THEN 0
    ELSE 1
END +
CASE
    WHEN (dashboard_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (menu_id IS NULL) THEN 0
    ELSE 1
END) = 1))
);


--
-- Name: menu_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.menu_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: menu_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.menu_items_id_seq OWNED BY public.menu_items.id;


--
-- Name: menus; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menus (
    id bigint NOT NULL,
    name character varying(255),
    description character varying(255),
    parent_id bigint,
    user_id bigint,
    is_global boolean DEFAULT false,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: menus_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.menus_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: menus_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.menus_id_seq OWNED BY public.menus.id;


--
-- Name: metric_display_order; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metric_display_order (
    id bigint NOT NULL,
    metric character varying(255),
    registry_metric character varying(255),
    args jsonb DEFAULT '{}'::jsonb,
    category_id bigint NOT NULL,
    group_id bigint,
    display_order integer NOT NULL,
    source_type character varying(255) DEFAULT 'code'::character varying,
    code_module character varying(255),
    metric_registry_id bigint,
    ui_human_readable_name character varying(255),
    chart_style character varying(255) DEFAULT 'line'::character varying,
    unit character varying(255) DEFAULT ''::character varying,
    description text,
    type character varying(255) DEFAULT 'metric'::character varying,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    ui_key character varying(255)
);


--
-- Name: metric_display_order_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metric_display_order_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metric_display_order_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metric_display_order_id_seq OWNED BY public.metric_display_order.id;


--
-- Name: metric_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metric_registry (
    id bigint NOT NULL,
    metric character varying(255) NOT NULL,
    internal_metric character varying(255) NOT NULL,
    human_readable_name character varying(255) NOT NULL,
    aliases jsonb,
    tables jsonb NOT NULL,
    is_template boolean DEFAULT false NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
    fixed_parameters jsonb DEFAULT '{}'::jsonb,
    is_timebound boolean NOT NULL,
    exposed_environments character varying(255) DEFAULT 'all'::character varying NOT NULL,
    version character varying(255),
    selectors jsonb,
    required_selectors jsonb,
    access character varying(255) NOT NULL,
    sanbase_min_plan character varying(255) DEFAULT 'free'::character varying NOT NULL,
    sanapi_min_plan character varying(255) DEFAULT 'free'::character varying NOT NULL,
    default_aggregation character varying(255) NOT NULL,
    min_interval character varying(255) NOT NULL,
    has_incomplete_data boolean NOT NULL,
    data_type character varying(255) DEFAULT 'timeseries'::character varying NOT NULL,
    docs jsonb,
    is_hidden boolean DEFAULT false NOT NULL,
    is_deprecated boolean DEFAULT false NOT NULL,
    hard_deprecate_after timestamp(0) without time zone DEFAULT NULL::timestamp without time zone,
    deprecation_note text,
    inserted_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    status character varying(255) DEFAULT 'released'::character varying NOT NULL,
    is_verified boolean DEFAULT true NOT NULL,
    sync_status character varying(255) DEFAULT 'synced'::character varying NOT NULL,
    last_sync_datetime timestamp(0) without time zone
);


--
-- Name: metric_registry_change_suggestions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metric_registry_change_suggestions (
    id bigint NOT NULL,
    metric_registry_id bigint,
    status character varying(255) DEFAULT 'pending_approval'::character varying NOT NULL,
    changes text NOT NULL,
    notes text,
    submitted_by character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: metric_registry_change_suggestions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metric_registry_change_suggestions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metric_registry_change_suggestions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metric_registry_change_suggestions_id_seq OWNED BY public.metric_registry_change_suggestions.id;


--
-- Name: metric_registry_changelog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metric_registry_changelog (
    id bigint NOT NULL,
    metric_registry_id bigint,
    old text,
    new text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    change_trigger character varying(255)
);


--
-- Name: metric_registry_changelog_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metric_registry_changelog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metric_registry_changelog_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metric_registry_changelog_id_seq OWNED BY public.metric_registry_changelog.id;


--
-- Name: metric_registry_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metric_registry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metric_registry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metric_registry_id_seq OWNED BY public.metric_registry.id;


--
-- Name: metric_registry_sync_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metric_registry_sync_runs (
    id bigint NOT NULL,
    uuid character varying(255),
    sync_type character varying(255),
    status character varying(255),
    content text,
    actual_changes text,
    errors text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    is_dry_run boolean DEFAULT false,
    started_by character varying(255)
);


--
-- Name: metric_registry_sync_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metric_registry_sync_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metric_registry_sync_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metric_registry_sync_runs_id_seq OWNED BY public.metric_registry_sync_runs.id;


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
-- Name: monitored_twitter_handles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.monitored_twitter_handles (
    id bigint NOT NULL,
    handle character varying(255) NOT NULL,
    origin character varying(255) NOT NULL,
    notes text,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    status character varying(255) DEFAULT 'pending_approval'::character varying,
    comment text
);


--
-- Name: monitored_twitter_handles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.monitored_twitter_handles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: monitored_twitter_handles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.monitored_twitter_handles_id_seq OWNED BY public.monitored_twitter_handles.id;


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
-- Name: notification_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_templates (
    id bigint NOT NULL,
    channel character varying(255),
    action character varying(255),
    step character varying(255),
    template text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    mime_type character varying(255) DEFAULT 'text/plain'::character varying,
    required_params character varying(255)[] DEFAULT ARRAY[]::character varying[]
);


--
-- Name: notification_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_templates_id_seq OWNED BY public.notification_templates.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id bigint NOT NULL,
    action character varying(255),
    params jsonb,
    step character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    channel character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'available'::character varying NOT NULL,
    job_id bigint,
    is_manual boolean DEFAULT false NOT NULL,
    metric_registry_id bigint,
    notification_template_id bigint,
    scheduled_at timestamp(0) without time zone
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
-- Name: oban_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags character varying(255)[] DEFAULT ARRAY[]::character varying[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT priority_range CHECK (((priority >= 0) AND (priority <= 3))),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.oban_jobs IS '11';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;


--
-- Name: oban_peers; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


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
    "order" integer DEFAULT 0,
    is_private boolean DEFAULT false,
    has_custom_restrictions boolean DEFAULT false NOT NULL,
    restrictions jsonb,
    is_ppp boolean DEFAULT false
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
    chart_configuration_for_event_id bigint,
    is_deleted boolean DEFAULT false,
    is_hidden boolean DEFAULT false
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
-- Name: presigned_s3_urls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.presigned_s3_urls (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    bucket character varying(255) NOT NULL,
    object character varying(255) NOT NULL,
    presigned_url text NOT NULL,
    expires_at timestamp(0) without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: presigned_s3_urls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.presigned_s3_urls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: presigned_s3_urls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.presigned_s3_urls_id_seq OWNED BY public.presigned_s3_urls.id;


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
    dark_logo_url character varying(255),
    telegram_chat_id integer,
    discord_link character varying(255),
    ecosystem character varying(255),
    ecosystem_full_path character varying(255),
    multichain_project_group_key character varying(255) DEFAULT NULL::character varying,
    deployed_on_ecosystem_id bigint,
    hidden_since timestamp(0) without time zone,
    hidden_reason text
);


--
-- Name: project_ecosystem_labels_change_suggestions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_ecosystem_labels_change_suggestions (
    id bigint NOT NULL,
    project_id bigint,
    added_ecosystems character varying(255)[],
    removed_ecosystems character varying(255)[],
    notes text,
    status character varying(255) DEFAULT 'pending_approval'::character varying,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: project_ecosystem_labels_change_suggestions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_ecosystem_labels_change_suggestions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_ecosystem_labels_change_suggestions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_ecosystem_labels_change_suggestions_id_seq OWNED BY public.project_ecosystem_labels_change_suggestions.id;


--
-- Name: project_ecosystem_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_ecosystem_mappings (
    id bigint NOT NULL,
    project_id bigint NOT NULL,
    ecosystem_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: project_ecosystem_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_ecosystem_mappings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_ecosystem_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_ecosystem_mappings_id_seq OWNED BY public.project_ecosystem_mappings.id;


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
-- Name: project_github_organizations_change_suggestions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_github_organizations_change_suggestions (
    id bigint NOT NULL,
    project_id bigint,
    added_organizations character varying(255)[],
    removed_organizations character varying(255)[],
    notes text,
    status character varying(255) DEFAULT 'pending_approval'::character varying,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: project_github_organizations_change_suggestions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.project_github_organizations_change_suggestions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_github_organizations_change_suggestions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.project_github_organizations_change_suggestions_id_seq OWNED BY public.project_github_organizations_change_suggestions.id;


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
    query text,
    autogenerated_query text,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
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
-- Name: pumpkins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pumpkins (
    id bigint NOT NULL,
    collected integer DEFAULT 0,
    coupon character varying(255),
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    pages character varying(255)[] DEFAULT ARRAY[]::character varying[]
);


--
-- Name: pumpkins_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pumpkins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pumpkins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pumpkins_id_seq OWNED BY public.pumpkins.id;


--
-- Name: queries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.queries (
    id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    origin_id integer,
    origin_uuid character varying(255),
    name text,
    description text,
    is_public boolean DEFAULT true,
    settings jsonb,
    sql_query_text text DEFAULT ''::text,
    sql_query_parameters jsonb DEFAULT '{}'::jsonb,
    user_id bigint NOT NULL,
    is_hidden boolean DEFAULT false,
    is_deleted boolean DEFAULT false,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: queries_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.queries_cache (
    id bigint NOT NULL,
    query_id bigint,
    user_id bigint,
    data text,
    query_hash text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: queries_cache_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.queries_cache_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: queries_cache_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.queries_cache_id_seq OWNED BY public.queries_cache.id;


--
-- Name: queries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.queries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: queries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.queries_id_seq OWNED BY public.queries.id;


--
-- Name: questionnaire_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questionnaire_answers (
    uuid uuid NOT NULL,
    user_id bigint NOT NULL,
    question_uuid uuid NOT NULL,
    answer jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: questionnaire_questions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questionnaire_questions (
    uuid uuid NOT NULL,
    questionnaire_uuid uuid NOT NULL,
    "order" integer NOT NULL,
    question character varying(255) NOT NULL,
    type public.question_type DEFAULT 'open_text'::public.question_type NOT NULL,
    answer_options jsonb DEFAULT '{}'::jsonb NOT NULL,
    has_extra_open_text_answer boolean DEFAULT false NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: questionnaires; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questionnaires (
    uuid uuid NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    ends_at timestamp(0) without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    is_deleted boolean DEFAULT false
);


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
-- Name: san_burn_credit_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.san_burn_credit_transactions (
    id bigint NOT NULL,
    address character varying(255),
    trx_hash character varying(255),
    san_amount double precision,
    san_price double precision,
    credit_amount double precision,
    trx_datetime timestamp(0) without time zone,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: san_burn_credit_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.san_burn_credit_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: san_burn_credit_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.san_burn_credit_transactions_id_seq OWNED BY public.san_burn_credit_transactions.id;


--
-- Name: sanr_emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sanr_emails (
    id bigint NOT NULL,
    email character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: sanr_emails_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sanr_emails_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sanr_emails_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sanr_emails_id_seq OWNED BY public.sanr_emails.id;


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
-- Name: scheduled_deprecation_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scheduled_deprecation_notifications (
    id bigint NOT NULL,
    deprecation_date date NOT NULL,
    contact_list_name character varying(255) NOT NULL,
    api_endpoint character varying(255) NOT NULL,
    links character varying(255)[] NOT NULL,
    schedule_email_subject character varying(255) NOT NULL,
    schedule_email_html text NOT NULL,
    schedule_email_scheduled_at timestamp(0) without time zone NOT NULL,
    schedule_email_job_id character varying(255),
    schedule_email_sent_at timestamp(0) without time zone,
    schedule_email_dispatch_status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    reminder_email_subject character varying(255) NOT NULL,
    reminder_email_html text NOT NULL,
    reminder_email_scheduled_at timestamp(0) without time zone NOT NULL,
    reminder_email_job_id character varying(255),
    reminder_email_sent_at timestamp(0) without time zone,
    reminder_email_dispatch_status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    executed_email_subject character varying(255) NOT NULL,
    executed_email_html text NOT NULL,
    executed_email_scheduled_at timestamp(0) without time zone NOT NULL,
    executed_email_job_id character varying(255),
    executed_email_sent_at timestamp(0) without time zone,
    executed_email_dispatch_status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: scheduled_deprecation_notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.scheduled_deprecation_notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scheduled_deprecation_notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.scheduled_deprecation_notifications_id_seq OWNED BY public.scheduled_deprecation_notifications.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp without time zone
);


--
-- Name: seen_timeline_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seen_timeline_events (
    id bigint NOT NULL,
    seen_at timestamp(0) without time zone,
    user_id bigint,
    event_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: seen_timeline_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seen_timeline_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seen_timeline_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seen_timeline_events_id_seq OWNED BY public.seen_timeline_events.id;


--
-- Name: shared_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shared_access_tokens (
    id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    user_id bigint NOT NULL,
    chart_configuration_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: shared_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.shared_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: shared_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.shared_access_tokens_id_seq OWNED BY public.shared_access_tokens.id;


--
-- Name: sheets_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sheets_templates (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    url character varying(255) NOT NULL,
    is_pro boolean DEFAULT false NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: sheets_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sheets_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sheets_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sheets_templates_id_seq OWNED BY public.sheets_templates.id;


--
-- Name: short_urls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.short_urls (
    id bigint NOT NULL,
    short_url character varying(255) NOT NULL,
    full_url text NOT NULL,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    data character varying(255)
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
-- Name: subscription_timeseries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_timeseries (
    id bigint NOT NULL,
    subscriptions jsonb[],
    stats jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: subscription_timeseries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscription_timeseries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscription_timeseries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscription_timeseries_id_seq OWNED BY public.subscription_timeseries.id;


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
    updated_at timestamp without time zone,
    type public.subscription_type DEFAULT 'fiat'::public.subscription_type NOT NULL
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
    updated_at timestamp without time zone NOT NULL,
    type public.table_configuration_type
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
-- Name: thread_ai_context; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.thread_ai_context (
    id bigint NOT NULL,
    discord_user character varying(255),
    guild_id character varying(255),
    guild_name character varying(255),
    channel_id character varying(255),
    channel_name character varying(255),
    thread_id character varying(255),
    thread_name character varying(255),
    question text,
    answer text,
    votes_pos integer DEFAULT 0,
    votes_neg integer DEFAULT 0,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    elapsed_time double precision,
    tokens_request integer,
    tokens_response integer,
    tokens_total integer,
    error_message character varying(255),
    total_cost double precision
);


--
-- Name: thread_ai_context_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.thread_ai_context_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: thread_ai_context_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.thread_ai_context_id_seq OWNED BY public.thread_ai_context.id;


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
-- Name: tweet_predictions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tweet_predictions (
    id bigint NOT NULL,
    tweet_id character varying(255) NOT NULL,
    "timestamp" timestamp(0) without time zone NOT NULL,
    text text NOT NULL,
    url character varying(255) NOT NULL,
    is_prediction boolean NOT NULL,
    is_interesting boolean DEFAULT false NOT NULL,
    screen_name character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: tweet_predictions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tweet_predictions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tweet_predictions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tweet_predictions_id_seq OWNED BY public.tweet_predictions.id;


--
-- Name: ui_metadata_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ui_metadata_categories (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    display_order integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: ui_metadata_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ui_metadata_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ui_metadata_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ui_metadata_categories_id_seq OWNED BY public.ui_metadata_categories.id;


--
-- Name: ui_metadata_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ui_metadata_groups (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    category_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: ui_metadata_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ui_metadata_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ui_metadata_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ui_metadata_groups_id_seq OWNED BY public.ui_metadata_groups.id;


--
-- Name: user_affiliate_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_affiliate_details (
    id bigint NOT NULL,
    telegram_handle character varying(255) NOT NULL,
    marketing_channels text,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: user_affiliate_details_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_affiliate_details_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_affiliate_details_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_affiliate_details_id_seq OWNED BY public.user_affiliate_details.id;


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
-- Name: user_entity_interactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_entity_interactions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    entity_type character varying(255) NOT NULL,
    entity_id integer NOT NULL,
    interaction_type character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: user_entity_interactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_entity_interactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_entity_interactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_entity_interactions_id_seq OWNED BY public.user_entity_interactions.id;


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
    is_notification_disabled boolean DEFAULT false,
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
    slug character varying(255),
    is_monitored boolean DEFAULT false,
    table_configuration_id bigint,
    description text,
    type public.watchlist_type DEFAULT 'project'::public.watchlist_type NOT NULL,
    is_screener boolean DEFAULT false,
    is_deleted boolean DEFAULT false,
    is_hidden boolean DEFAULT false
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
-- Name: user_promo_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_promo_codes (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    coupon character varying(255) NOT NULL,
    campaign character varying(255),
    percent_off integer,
    max_redemptions integer DEFAULT 1,
    times_redeemed integer DEFAULT 0,
    redeem_by timestamp(0) without time zone,
    metadata jsonb,
    extra_data jsonb,
    valid boolean DEFAULT true NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: user_promo_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_promo_codes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_promo_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_promo_codes_id_seq OWNED BY public.user_promo_codes.id;


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
    updated_at timestamp without time zone NOT NULL,
    is_deleted boolean DEFAULT false,
    is_hidden boolean DEFAULT false
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
-- Name: user_uniswap_staking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_uniswap_staking (
    id bigint NOT NULL,
    san_staked double precision,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: user_uniswap_staking_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_uniswap_staking_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_uniswap_staking_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_uniswap_staking_id_seq OWNED BY public.user_uniswap_staking.id;


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
    is_registered boolean DEFAULT false,
    is_superuser boolean DEFAULT false,
    twitter_id character varying(255) DEFAULT NULL::character varying,
    name character varying(255),
    registration_state jsonb DEFAULT '{"state": "init"}'::jsonb,
    metric_access_level character varying(255) DEFAULT 'released'::character varying NOT NULL,
    description text,
    website_url character varying(255),
    twitter_handle character varying(255),
    feature_access_level character varying(255) DEFAULT 'released'::character varying NOT NULL
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
-- Name: versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.versions (
    id bigint NOT NULL,
    patch bytea,
    entity_id integer,
    entity_schema character varying(255),
    action character varying(255),
    recorded_at timestamp(0) without time zone,
    rollback boolean DEFAULT false,
    user_id bigint
);


--
-- Name: versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.versions_id_seq OWNED BY public.versions.id;


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
    chart_configuration_id bigint,
    watchlist_id bigint,
    user_trigger_id bigint,
    dashboard_id bigint,
    query_id bigint,
    CONSTRAINT only_one_fk CHECK ((((((((
CASE
    WHEN (post_id IS NULL) THEN 0
    ELSE 1
END +
CASE
    WHEN (timeline_event_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (chart_configuration_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (watchlist_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (user_trigger_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (dashboard_id IS NULL) THEN 0
    ELSE 1
END) +
CASE
    WHEN (query_id IS NULL) THEN 0
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
-- Name: wallet_hunters_bounties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_hunters_bounties (
    id bigint NOT NULL,
    title character varying(255),
    description text,
    duration character varying(255),
    proposals_count integer,
    proposal_reward integer,
    transaction_id character varying(255),
    transaction_status character varying(255),
    hash_digest character varying(255),
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: wallet_hunters_bounties_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wallet_hunters_bounties_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallet_hunters_bounties_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wallet_hunters_bounties_id_seq OWNED BY public.wallet_hunters_bounties.id;


--
-- Name: wallet_hunters_proposals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_hunters_proposals (
    id bigint NOT NULL,
    title text,
    text text,
    proposal_id integer,
    hunter_address character varying(255),
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    proposed_address character varying(255),
    user_labels character varying(255)[] DEFAULT ARRAY[]::character varying[],
    transaction_id character varying(255) NOT NULL,
    transaction_status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    bounty_id bigint
);


--
-- Name: wallet_hunters_proposals_comments_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_hunters_proposals_comments_mapping (
    id bigint NOT NULL,
    comment_id bigint,
    proposal_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: wallet_hunters_proposals_comments_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wallet_hunters_proposals_comments_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallet_hunters_proposals_comments_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wallet_hunters_proposals_comments_mapping_id_seq OWNED BY public.wallet_hunters_proposals_comments_mapping.id;


--
-- Name: wallet_hunters_proposals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wallet_hunters_proposals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallet_hunters_proposals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wallet_hunters_proposals_id_seq OWNED BY public.wallet_hunters_proposals.id;


--
-- Name: wallet_hunters_relays_quota; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_hunters_relays_quota (
    id bigint NOT NULL,
    proposals_used integer,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    votes_used integer DEFAULT 0,
    last_voted timestamp(0) without time zone,
    proposals_earned integer DEFAULT 0
);


--
-- Name: wallet_hunters_relays_quota_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wallet_hunters_relays_quota_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallet_hunters_relays_quota_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wallet_hunters_relays_quota_id_seq OWNED BY public.wallet_hunters_relays_quota.id;


--
-- Name: wallet_hunters_votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_hunters_votes (
    id bigint NOT NULL,
    proposal_id integer,
    transaction_id character varying(255),
    transaction_status character varying(255) DEFAULT 'pending'::character varying,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: wallet_hunters_votes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wallet_hunters_votes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallet_hunters_votes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wallet_hunters_votes_id_seq OWNED BY public.wallet_hunters_votes.id;


--
-- Name: watchlist_comments_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.watchlist_comments_mapping (
    id bigint NOT NULL,
    comment_id bigint,
    watchlist_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: watchlist_comments_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.watchlist_comments_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: watchlist_comments_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.watchlist_comments_mapping_id_seq OWNED BY public.watchlist_comments_mapping.id;


--
-- Name: watchlist_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.watchlist_settings (
    user_id bigint NOT NULL,
    watchlist_id bigint NOT NULL,
    settings jsonb
);


--
-- Name: webinar_registrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webinar_registrations (
    id bigint NOT NULL,
    user_id bigint,
    webinar_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: webinar_registrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.webinar_registrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: webinar_registrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.webinar_registrations_id_seq OWNED BY public.webinar_registrations.id;


--
-- Name: webinars; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webinars (
    id bigint NOT NULL,
    title character varying(255),
    description text,
    url character varying(255),
    image_url character varying(255),
    start_time timestamp(0) without time zone,
    end_time timestamp(0) without time zone,
    is_pro boolean DEFAULT false NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: webinars_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.webinars_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: webinars_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.webinars_id_seq OWNED BY public.webinars.id;


--
-- Name: access_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_attempts ALTER COLUMN id SET DEFAULT nextval('public.access_attempts_id_seq'::regclass);


--
-- Name: active_widgets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_widgets ALTER COLUMN id SET DEFAULT nextval('public.active_widgets_id_seq'::regclass);


--
-- Name: ai_context id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_context ALTER COLUMN id SET DEFAULT nextval('public.ai_context_id_seq'::regclass);


--
-- Name: ai_gen_code id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_gen_code ALTER COLUMN id SET DEFAULT nextval('public.ai_gen_code_id_seq'::regclass);


--
-- Name: alpha_naratives_emails id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alpha_naratives_emails ALTER COLUMN id SET DEFAULT nextval('public.alpha_naratives_emails_id_seq'::regclass);


--
-- Name: api_call_limits id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_call_limits ALTER COLUMN id SET DEFAULT nextval('public.api_call_limits_id_seq'::regclass);


--
-- Name: asset_exchange_pairs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_exchange_pairs ALTER COLUMN id SET DEFAULT nextval('public.asset_exchange_pairs_id_seq'::regclass);


--
-- Name: available_metrics_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.available_metrics_data ALTER COLUMN id SET DEFAULT nextval('public.available_metrics_data_id_seq'::regclass);


--
-- Name: blockchain_address_comments_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_comments_mapping ALTER COLUMN id SET DEFAULT nextval('public.blockchain_address_comments_mapping_id_seq'::regclass);


--
-- Name: blockchain_address_labels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_labels ALTER COLUMN id SET DEFAULT nextval('public.blockchain_address_labels_id_seq'::regclass);


--
-- Name: blockchain_address_user_pairs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_user_pairs ALTER COLUMN id SET DEFAULT nextval('public.blockchain_address_user_pairs_id_seq'::regclass);


--
-- Name: blockchain_address_user_pairs_labels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_user_pairs_labels ALTER COLUMN id SET DEFAULT nextval('public.blockchain_address_user_pairs_labels_id_seq'::regclass);


--
-- Name: blockchain_addresses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_addresses ALTER COLUMN id SET DEFAULT nextval('public.blockchain_addresses_id_seq'::regclass);


--
-- Name: chart_configuration_comments_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configuration_comments_mapping ALTER COLUMN id SET DEFAULT nextval('public.chart_configuration_comments_mapping_id_seq'::regclass);


--
-- Name: chart_configurations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configurations ALTER COLUMN id SET DEFAULT nextval('public.chart_configurations_id_seq'::regclass);


--
-- Name: clickhouse_query_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clickhouse_query_executions ALTER COLUMN id SET DEFAULT nextval('public.clickhouse_query_executions_id_seq'::regclass);


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
-- Name: cryptocompare_exporter_progress id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cryptocompare_exporter_progress ALTER COLUMN id SET DEFAULT nextval('public.cryptocompare_exporter_progress_id_seq'::regclass);


--
-- Name: currencies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.currencies ALTER COLUMN id SET DEFAULT nextval('public.currencies_id_seq'::regclass);


--
-- Name: dashboard_comments_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_comments_mapping ALTER COLUMN id SET DEFAULT nextval('public.dashboard_comments_mapping_id_seq'::regclass);


--
-- Name: dashboards id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards ALTER COLUMN id SET DEFAULT nextval('public.dashboards_id_seq'::regclass);


--
-- Name: dashboards_cache id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards_cache ALTER COLUMN id SET DEFAULT nextval('public.dashboards_cache_id_seq'::regclass);


--
-- Name: dashboards_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards_history ALTER COLUMN id SET DEFAULT nextval('public.dashboards_history_id_seq'::regclass);


--
-- Name: discord_dashboards id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discord_dashboards ALTER COLUMN id SET DEFAULT nextval('public.discord_dashboards_id_seq'::regclass);


--
-- Name: ecosystems id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ecosystems ALTER COLUMN id SET DEFAULT nextval('public.ecosystems_id_seq'::regclass);


--
-- Name: email_login_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_login_attempts ALTER COLUMN id SET DEFAULT nextval('public.email_login_attempts_id_seq'::regclass);


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
-- Name: finished_oban_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finished_oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.finished_oban_jobs_id_seq'::regclass);


--
-- Name: free_form_json_storage id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.free_form_json_storage ALTER COLUMN id SET DEFAULT nextval('public.free_form_json_storage_id_seq'::regclass);


--
-- Name: geoip_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geoip_data ALTER COLUMN id SET DEFAULT nextval('public.geoip_data_id_seq'::regclass);


--
-- Name: github_organizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_organizations ALTER COLUMN id SET DEFAULT nextval('public.github_organizations_id_seq'::regclass);


--
-- Name: gpt_router id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gpt_router ALTER COLUMN id SET DEFAULT nextval('public.gpt_router_id_seq'::regclass);


--
-- Name: ico_currencies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ico_currencies ALTER COLUMN id SET DEFAULT nextval('public.ico_currencies_id_seq'::regclass);


--
-- Name: icos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.icos ALTER COLUMN id SET DEFAULT nextval('public.icos_id_seq'::regclass);


--
-- Name: images id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.images ALTER COLUMN id SET DEFAULT nextval('public.images_id_seq'::regclass);


--
-- Name: infrastructures id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructures ALTER COLUMN id SET DEFAULT nextval('public.infrastructures_id_seq'::regclass);


--
-- Name: latest_coinmarketcap_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.latest_coinmarketcap_data ALTER COLUMN id SET DEFAULT nextval('public.latest_coinmarketcap_data_id_seq'::regclass);


--
-- Name: linked_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linked_users ALTER COLUMN id SET DEFAULT nextval('public.linked_users_id_seq'::regclass);


--
-- Name: linked_users_candidates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linked_users_candidates ALTER COLUMN id SET DEFAULT nextval('public.linked_users_candidates_id_seq'::regclass);


--
-- Name: list_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items ALTER COLUMN id SET DEFAULT nextval('public.list_items_id_seq'::regclass);


--
-- Name: market_segments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_segments ALTER COLUMN id SET DEFAULT nextval('public.market_segments_id_seq'::regclass);


--
-- Name: menu_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items ALTER COLUMN id SET DEFAULT nextval('public.menu_items_id_seq'::regclass);


--
-- Name: menus id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menus ALTER COLUMN id SET DEFAULT nextval('public.menus_id_seq'::regclass);


--
-- Name: metric_display_order id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_display_order ALTER COLUMN id SET DEFAULT nextval('public.metric_display_order_id_seq'::regclass);


--
-- Name: metric_registry id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_registry ALTER COLUMN id SET DEFAULT nextval('public.metric_registry_id_seq'::regclass);


--
-- Name: metric_registry_change_suggestions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_registry_change_suggestions ALTER COLUMN id SET DEFAULT nextval('public.metric_registry_change_suggestions_id_seq'::regclass);


--
-- Name: metric_registry_changelog id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_registry_changelog ALTER COLUMN id SET DEFAULT nextval('public.metric_registry_changelog_id_seq'::regclass);


--
-- Name: metric_registry_sync_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_registry_sync_runs ALTER COLUMN id SET DEFAULT nextval('public.metric_registry_sync_runs_id_seq'::regclass);


--
-- Name: metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics ALTER COLUMN id SET DEFAULT nextval('public.metrics_id_seq'::regclass);


--
-- Name: monitored_twitter_handles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monitored_twitter_handles ALTER COLUMN id SET DEFAULT nextval('public.monitored_twitter_handles_id_seq'::regclass);


--
-- Name: newsletter_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.newsletter_tokens ALTER COLUMN id SET DEFAULT nextval('public.newsletter_tokens_id_seq'::regclass);


--
-- Name: notification_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_templates ALTER COLUMN id SET DEFAULT nextval('public.notification_templates_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);


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
-- Name: presigned_s3_urls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presigned_s3_urls ALTER COLUMN id SET DEFAULT nextval('public.presigned_s3_urls_id_seq'::regclass);


--
-- Name: price_migration_tmp id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_migration_tmp ALTER COLUMN id SET DEFAULT nextval('public.price_migration_tmp_id_seq'::regclass);


--
-- Name: price_scraping_progress id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_scraping_progress ALTER COLUMN id SET DEFAULT nextval('public.price_scraping_progress_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: project id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project ALTER COLUMN id SET DEFAULT nextval('public.project_id_seq'::regclass);


--
-- Name: project_ecosystem_labels_change_suggestions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_ecosystem_labels_change_suggestions ALTER COLUMN id SET DEFAULT nextval('public.project_ecosystem_labels_change_suggestions_id_seq'::regclass);


--
-- Name: project_ecosystem_mappings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_ecosystem_mappings ALTER COLUMN id SET DEFAULT nextval('public.project_ecosystem_mappings_id_seq'::regclass);


--
-- Name: project_eth_address id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_eth_address ALTER COLUMN id SET DEFAULT nextval('public.project_eth_address_id_seq'::regclass);


--
-- Name: project_github_organizations_change_suggestions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_github_organizations_change_suggestions ALTER COLUMN id SET DEFAULT nextval('public.project_github_organizations_change_suggestions_id_seq'::regclass);


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
-- Name: pumpkins id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pumpkins ALTER COLUMN id SET DEFAULT nextval('public.pumpkins_id_seq'::regclass);


--
-- Name: queries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queries ALTER COLUMN id SET DEFAULT nextval('public.queries_id_seq'::regclass);


--
-- Name: queries_cache id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queries_cache ALTER COLUMN id SET DEFAULT nextval('public.queries_cache_id_seq'::regclass);


--
-- Name: reports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports ALTER COLUMN id SET DEFAULT nextval('public.reports_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: san_burn_credit_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.san_burn_credit_transactions ALTER COLUMN id SET DEFAULT nextval('public.san_burn_credit_transactions_id_seq'::regclass);


--
-- Name: sanr_emails id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sanr_emails ALTER COLUMN id SET DEFAULT nextval('public.sanr_emails_id_seq'::regclass);


--
-- Name: schedule_rescrape_prices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_rescrape_prices ALTER COLUMN id SET DEFAULT nextval('public.schedule_rescrape_prices_id_seq'::regclass);


--
-- Name: scheduled_deprecation_notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_deprecation_notifications ALTER COLUMN id SET DEFAULT nextval('public.scheduled_deprecation_notifications_id_seq'::regclass);


--
-- Name: seen_timeline_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seen_timeline_events ALTER COLUMN id SET DEFAULT nextval('public.seen_timeline_events_id_seq'::regclass);


--
-- Name: shared_access_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shared_access_tokens ALTER COLUMN id SET DEFAULT nextval('public.shared_access_tokens_id_seq'::regclass);


--
-- Name: sheets_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sheets_templates ALTER COLUMN id SET DEFAULT nextval('public.sheets_templates_id_seq'::regclass);


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
-- Name: subscription_timeseries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_timeseries ALTER COLUMN id SET DEFAULT nextval('public.subscription_timeseries_id_seq'::regclass);


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
-- Name: thread_ai_context id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thread_ai_context ALTER COLUMN id SET DEFAULT nextval('public.thread_ai_context_id_seq'::regclass);


--
-- Name: timeline_event_comments_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_event_comments_mapping ALTER COLUMN id SET DEFAULT nextval('public.timeline_event_comments_mapping_id_seq'::regclass);


--
-- Name: timeline_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events ALTER COLUMN id SET DEFAULT nextval('public.timeline_events_id_seq'::regclass);


--
-- Name: tweet_predictions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tweet_predictions ALTER COLUMN id SET DEFAULT nextval('public.tweet_predictions_id_seq'::regclass);


--
-- Name: ui_metadata_categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ui_metadata_categories ALTER COLUMN id SET DEFAULT nextval('public.ui_metadata_categories_id_seq'::regclass);


--
-- Name: ui_metadata_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ui_metadata_groups ALTER COLUMN id SET DEFAULT nextval('public.ui_metadata_groups_id_seq'::regclass);


--
-- Name: user_affiliate_details id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_affiliate_details ALTER COLUMN id SET DEFAULT nextval('public.user_affiliate_details_id_seq'::regclass);


--
-- Name: user_api_key_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_api_key_tokens ALTER COLUMN id SET DEFAULT nextval('public.user_api_key_tokens_id_seq'::regclass);


--
-- Name: user_entity_interactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_entity_interactions ALTER COLUMN id SET DEFAULT nextval('public.user_entity_interactions_id_seq'::regclass);


--
-- Name: user_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_events ALTER COLUMN id SET DEFAULT nextval('public.user_events_id_seq'::regclass);


--
-- Name: user_lists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lists ALTER COLUMN id SET DEFAULT nextval('public.user_lists_id_seq'::regclass);


--
-- Name: user_promo_codes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_promo_codes ALTER COLUMN id SET DEFAULT nextval('public.user_promo_codes_id_seq'::regclass);


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
-- Name: user_uniswap_staking id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_uniswap_staking ALTER COLUMN id SET DEFAULT nextval('public.user_uniswap_staking_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions ALTER COLUMN id SET DEFAULT nextval('public.versions_id_seq'::regclass);


--
-- Name: votes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes ALTER COLUMN id SET DEFAULT nextval('public.votes_id_seq'::regclass);


--
-- Name: wallet_hunters_bounties id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_bounties ALTER COLUMN id SET DEFAULT nextval('public.wallet_hunters_bounties_id_seq'::regclass);


--
-- Name: wallet_hunters_proposals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_proposals ALTER COLUMN id SET DEFAULT nextval('public.wallet_hunters_proposals_id_seq'::regclass);


--
-- Name: wallet_hunters_proposals_comments_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_proposals_comments_mapping ALTER COLUMN id SET DEFAULT nextval('public.wallet_hunters_proposals_comments_mapping_id_seq'::regclass);


--
-- Name: wallet_hunters_relays_quota id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_relays_quota ALTER COLUMN id SET DEFAULT nextval('public.wallet_hunters_relays_quota_id_seq'::regclass);


--
-- Name: wallet_hunters_votes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_votes ALTER COLUMN id SET DEFAULT nextval('public.wallet_hunters_votes_id_seq'::regclass);


--
-- Name: watchlist_comments_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watchlist_comments_mapping ALTER COLUMN id SET DEFAULT nextval('public.watchlist_comments_mapping_id_seq'::regclass);


--
-- Name: webinar_registrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webinar_registrations ALTER COLUMN id SET DEFAULT nextval('public.webinar_registrations_id_seq'::regclass);


--
-- Name: webinars id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webinars ALTER COLUMN id SET DEFAULT nextval('public.webinars_id_seq'::regclass);


--
-- Name: access_attempts access_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_attempts
    ADD CONSTRAINT access_attempts_pkey PRIMARY KEY (id);


--
-- Name: active_widgets active_widgets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_widgets
    ADD CONSTRAINT active_widgets_pkey PRIMARY KEY (id);


--
-- Name: ai_context ai_context_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_context
    ADD CONSTRAINT ai_context_pkey PRIMARY KEY (id);


--
-- Name: ai_gen_code ai_gen_code_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_gen_code
    ADD CONSTRAINT ai_gen_code_pkey PRIMARY KEY (id);


--
-- Name: alpha_naratives_emails alpha_naratives_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alpha_naratives_emails
    ADD CONSTRAINT alpha_naratives_emails_pkey PRIMARY KEY (id);


--
-- Name: api_call_limits api_call_limits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_call_limits
    ADD CONSTRAINT api_call_limits_pkey PRIMARY KEY (id);


--
-- Name: asset_exchange_pairs asset_exchange_pairs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_exchange_pairs
    ADD CONSTRAINT asset_exchange_pairs_pkey PRIMARY KEY (id);


--
-- Name: available_metrics_data available_metrics_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.available_metrics_data
    ADD CONSTRAINT available_metrics_data_pkey PRIMARY KEY (id);


--
-- Name: blockchain_address_comments_mapping blockchain_address_comments_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_comments_mapping
    ADD CONSTRAINT blockchain_address_comments_mapping_pkey PRIMARY KEY (id);


--
-- Name: blockchain_address_labels blockchain_address_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_labels
    ADD CONSTRAINT blockchain_address_labels_pkey PRIMARY KEY (id);


--
-- Name: blockchain_address_user_pairs_labels blockchain_address_user_pairs_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_user_pairs_labels
    ADD CONSTRAINT blockchain_address_user_pairs_labels_pkey PRIMARY KEY (id);


--
-- Name: blockchain_address_user_pairs blockchain_address_user_pairs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_user_pairs
    ADD CONSTRAINT blockchain_address_user_pairs_pkey PRIMARY KEY (id);


--
-- Name: blockchain_addresses blockchain_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_addresses
    ADD CONSTRAINT blockchain_addresses_pkey PRIMARY KEY (id);


--
-- Name: chart_configuration_comments_mapping chart_configuration_comments_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configuration_comments_mapping
    ADD CONSTRAINT chart_configuration_comments_mapping_pkey PRIMARY KEY (id);


--
-- Name: chart_configurations chart_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configurations
    ADD CONSTRAINT chart_configurations_pkey PRIMARY KEY (id);


--
-- Name: chat_messages chat_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);


--
-- Name: chats chats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT chats_pkey PRIMARY KEY (id);


--
-- Name: clickhouse_query_executions clickhouse_query_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clickhouse_query_executions
    ADD CONSTRAINT clickhouse_query_executions_pkey PRIMARY KEY (id);


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
-- Name: cryptocompare_exporter_progress cryptocompare_exporter_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cryptocompare_exporter_progress
    ADD CONSTRAINT cryptocompare_exporter_progress_pkey PRIMARY KEY (id);


--
-- Name: currencies currencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.currencies
    ADD CONSTRAINT currencies_pkey PRIMARY KEY (id);


--
-- Name: dashboard_comments_mapping dashboard_comments_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_comments_mapping
    ADD CONSTRAINT dashboard_comments_mapping_pkey PRIMARY KEY (id);


--
-- Name: dashboard_query_mappings dashboard_query_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_query_mappings
    ADD CONSTRAINT dashboard_query_mappings_pkey PRIMARY KEY (id);


--
-- Name: dashboards_cache dashboards_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards_cache
    ADD CONSTRAINT dashboards_cache_pkey PRIMARY KEY (id);


--
-- Name: dashboards_history dashboards_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards_history
    ADD CONSTRAINT dashboards_history_pkey PRIMARY KEY (id);


--
-- Name: dashboards dashboards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards
    ADD CONSTRAINT dashboards_pkey PRIMARY KEY (id);


--
-- Name: discord_dashboards discord_dashboards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discord_dashboards
    ADD CONSTRAINT discord_dashboards_pkey PRIMARY KEY (id);


--
-- Name: ecosystems ecosystems_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ecosystems
    ADD CONSTRAINT ecosystems_pkey PRIMARY KEY (id);


--
-- Name: email_login_attempts email_login_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_login_attempts
    ADD CONSTRAINT email_login_attempts_pkey PRIMARY KEY (id);


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
-- Name: finished_oban_jobs finished_oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finished_oban_jobs
    ADD CONSTRAINT finished_oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: free_form_json_storage free_form_json_storage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.free_form_json_storage
    ADD CONSTRAINT free_form_json_storage_pkey PRIMARY KEY (id);


--
-- Name: geoip_data geoip_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geoip_data
    ADD CONSTRAINT geoip_data_pkey PRIMARY KEY (id);


--
-- Name: github_organizations github_organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_organizations
    ADD CONSTRAINT github_organizations_pkey PRIMARY KEY (id);


--
-- Name: gpt_router gpt_router_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gpt_router
    ADD CONSTRAINT gpt_router_pkey PRIMARY KEY (id);


--
-- Name: guardian_tokens guardian_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guardian_tokens
    ADD CONSTRAINT guardian_tokens_pkey PRIMARY KEY (jti);


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
-- Name: images images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.images
    ADD CONSTRAINT images_pkey PRIMARY KEY (id);


--
-- Name: infrastructures infrastructures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.infrastructures
    ADD CONSTRAINT infrastructures_pkey PRIMARY KEY (id);


--
-- Name: latest_coinmarketcap_data latest_coinmarketcap_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.latest_coinmarketcap_data
    ADD CONSTRAINT latest_coinmarketcap_data_pkey PRIMARY KEY (id);


--
-- Name: linked_users_candidates linked_users_candidates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linked_users_candidates
    ADD CONSTRAINT linked_users_candidates_pkey PRIMARY KEY (id);


--
-- Name: linked_users linked_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linked_users
    ADD CONSTRAINT linked_users_pkey PRIMARY KEY (id);


--
-- Name: list_items list_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT list_items_pkey PRIMARY KEY (id);


--
-- Name: market_segments market_segments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_segments
    ADD CONSTRAINT market_segments_pkey PRIMARY KEY (id);


--
-- Name: menu_items menu_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_pkey PRIMARY KEY (id);


--
-- Name: menus menus_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menus
    ADD CONSTRAINT menus_pkey PRIMARY KEY (id);


--
-- Name: metric_display_order metric_display_order_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_display_order
    ADD CONSTRAINT metric_display_order_pkey PRIMARY KEY (id);


--
-- Name: metric_registry_change_suggestions metric_registry_change_suggestions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_registry_change_suggestions
    ADD CONSTRAINT metric_registry_change_suggestions_pkey PRIMARY KEY (id);


--
-- Name: metric_registry_changelog metric_registry_changelog_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_registry_changelog
    ADD CONSTRAINT metric_registry_changelog_pkey PRIMARY KEY (id);


--
-- Name: metric_registry metric_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_registry
    ADD CONSTRAINT metric_registry_pkey PRIMARY KEY (id);


--
-- Name: metric_registry_sync_runs metric_registry_sync_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_registry_sync_runs
    ADD CONSTRAINT metric_registry_sync_runs_pkey PRIMARY KEY (id);


--
-- Name: metrics metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics
    ADD CONSTRAINT metrics_pkey PRIMARY KEY (id);


--
-- Name: monitored_twitter_handles monitored_twitter_handles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monitored_twitter_handles
    ADD CONSTRAINT monitored_twitter_handles_pkey PRIMARY KEY (id);


--
-- Name: newsletter_tokens newsletter_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.newsletter_tokens
    ADD CONSTRAINT newsletter_tokens_pkey PRIMARY KEY (id);


--
-- Name: notification_templates notification_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_templates
    ADD CONSTRAINT notification_templates_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: oban_peers oban_peers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_peers
    ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);


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
-- Name: presigned_s3_urls presigned_s3_urls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presigned_s3_urls
    ADD CONSTRAINT presigned_s3_urls_pkey PRIMARY KEY (id);


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
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: project_ecosystem_labels_change_suggestions project_ecosystem_labels_change_suggestions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_ecosystem_labels_change_suggestions
    ADD CONSTRAINT project_ecosystem_labels_change_suggestions_pkey PRIMARY KEY (id);


--
-- Name: project_ecosystem_mappings project_ecosystem_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_ecosystem_mappings
    ADD CONSTRAINT project_ecosystem_mappings_pkey PRIMARY KEY (id);


--
-- Name: project_eth_address project_eth_address_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_eth_address
    ADD CONSTRAINT project_eth_address_pkey PRIMARY KEY (id);


--
-- Name: project_github_organizations_change_suggestions project_github_organizations_change_suggestions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_github_organizations_change_suggestions
    ADD CONSTRAINT project_github_organizations_change_suggestions_pkey PRIMARY KEY (id);


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
-- Name: pumpkins pumpkins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pumpkins
    ADD CONSTRAINT pumpkins_pkey PRIMARY KEY (id);


--
-- Name: queries_cache queries_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queries_cache
    ADD CONSTRAINT queries_cache_pkey PRIMARY KEY (id);


--
-- Name: queries queries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queries
    ADD CONSTRAINT queries_pkey PRIMARY KEY (id);


--
-- Name: questionnaire_answers questionnaire_answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_answers
    ADD CONSTRAINT questionnaire_answers_pkey PRIMARY KEY (uuid);


--
-- Name: questionnaire_questions questionnaire_questions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_questions
    ADD CONSTRAINT questionnaire_questions_pkey PRIMARY KEY (uuid);


--
-- Name: questionnaires questionnaires_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaires
    ADD CONSTRAINT questionnaires_pkey PRIMARY KEY (uuid);


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
-- Name: san_burn_credit_transactions san_burn_credit_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.san_burn_credit_transactions
    ADD CONSTRAINT san_burn_credit_transactions_pkey PRIMARY KEY (id);


--
-- Name: sanr_emails sanr_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sanr_emails
    ADD CONSTRAINT sanr_emails_pkey PRIMARY KEY (id);


--
-- Name: schedule_rescrape_prices schedule_rescrape_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_rescrape_prices
    ADD CONSTRAINT schedule_rescrape_prices_pkey PRIMARY KEY (id);


--
-- Name: scheduled_deprecation_notifications scheduled_deprecation_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_deprecation_notifications
    ADD CONSTRAINT scheduled_deprecation_notifications_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: seen_timeline_events seen_timeline_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seen_timeline_events
    ADD CONSTRAINT seen_timeline_events_pkey PRIMARY KEY (id);


--
-- Name: shared_access_tokens shared_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shared_access_tokens
    ADD CONSTRAINT shared_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: sheets_templates sheets_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sheets_templates
    ADD CONSTRAINT sheets_templates_pkey PRIMARY KEY (id);


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
-- Name: subscription_timeseries subscription_timeseries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_timeseries
    ADD CONSTRAINT subscription_timeseries_pkey PRIMARY KEY (id);


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
-- Name: thread_ai_context thread_ai_context_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thread_ai_context
    ADD CONSTRAINT thread_ai_context_pkey PRIMARY KEY (id);


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
-- Name: tweet_predictions tweet_predictions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tweet_predictions
    ADD CONSTRAINT tweet_predictions_pkey PRIMARY KEY (id);


--
-- Name: ui_metadata_categories ui_metadata_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ui_metadata_categories
    ADD CONSTRAINT ui_metadata_categories_pkey PRIMARY KEY (id);


--
-- Name: ui_metadata_groups ui_metadata_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ui_metadata_groups
    ADD CONSTRAINT ui_metadata_groups_pkey PRIMARY KEY (id);


--
-- Name: user_affiliate_details user_affiliate_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_affiliate_details
    ADD CONSTRAINT user_affiliate_details_pkey PRIMARY KEY (id);


--
-- Name: user_api_key_tokens user_api_key_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_api_key_tokens
    ADD CONSTRAINT user_api_key_tokens_pkey PRIMARY KEY (id);


--
-- Name: user_entity_interactions user_entity_interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_entity_interactions
    ADD CONSTRAINT user_entity_interactions_pkey PRIMARY KEY (id);


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
-- Name: user_lists user_lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lists
    ADD CONSTRAINT user_lists_pkey PRIMARY KEY (id);


--
-- Name: user_promo_codes user_promo_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_promo_codes
    ADD CONSTRAINT user_promo_codes_pkey PRIMARY KEY (id);


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
-- Name: user_uniswap_staking user_uniswap_staking_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_uniswap_staking
    ADD CONSTRAINT user_uniswap_staking_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: versions versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_pkey PRIMARY KEY (id);


--
-- Name: votes votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_pkey PRIMARY KEY (id);


--
-- Name: wallet_hunters_bounties wallet_hunters_bounties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_bounties
    ADD CONSTRAINT wallet_hunters_bounties_pkey PRIMARY KEY (id);


--
-- Name: wallet_hunters_proposals_comments_mapping wallet_hunters_proposals_comments_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_proposals_comments_mapping
    ADD CONSTRAINT wallet_hunters_proposals_comments_mapping_pkey PRIMARY KEY (id);


--
-- Name: wallet_hunters_proposals wallet_hunters_proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_proposals
    ADD CONSTRAINT wallet_hunters_proposals_pkey PRIMARY KEY (id);


--
-- Name: wallet_hunters_relays_quota wallet_hunters_relays_quota_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_relays_quota
    ADD CONSTRAINT wallet_hunters_relays_quota_pkey PRIMARY KEY (id);


--
-- Name: wallet_hunters_votes wallet_hunters_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_votes
    ADD CONSTRAINT wallet_hunters_votes_pkey PRIMARY KEY (id);


--
-- Name: watchlist_comments_mapping watchlist_comments_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watchlist_comments_mapping
    ADD CONSTRAINT watchlist_comments_mapping_pkey PRIMARY KEY (id);


--
-- Name: watchlist_settings watchlist_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watchlist_settings
    ADD CONSTRAINT watchlist_settings_pkey PRIMARY KEY (user_id, watchlist_id);


--
-- Name: webinar_registrations webinar_registrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webinar_registrations
    ADD CONSTRAINT webinar_registrations_pkey PRIMARY KEY (id);


--
-- Name: webinars webinars_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webinars
    ADD CONSTRAINT webinars_pkey PRIMARY KEY (id);


--
-- Name: access_attempts_type_ip_address_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX access_attempts_type_ip_address_inserted_at_index ON public.access_attempts USING btree (type, ip_address, inserted_at);


--
-- Name: access_attempts_type_user_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX access_attempts_type_user_id_inserted_at_index ON public.access_attempts USING btree (type, user_id, inserted_at);


--
-- Name: alpha_naratives_emails_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX alpha_naratives_emails_email_index ON public.alpha_naratives_emails USING btree (email);


--
-- Name: api_call_limits_remote_ip_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX api_call_limits_remote_ip_index ON public.api_call_limits USING btree (remote_ip);


--
-- Name: api_call_limits_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX api_call_limits_user_id_index ON public.api_call_limits USING btree (user_id);


--
-- Name: asset_exchange_pairs_base_asset_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX asset_exchange_pairs_base_asset_index ON public.asset_exchange_pairs USING btree (base_asset);


--
-- Name: asset_exchange_pairs_base_asset_quote_asset_exchange_source_ind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX asset_exchange_pairs_base_asset_quote_asset_exchange_source_ind ON public.asset_exchange_pairs USING btree (base_asset, quote_asset, exchange, source);


--
-- Name: asset_exchange_pairs_exchange_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX asset_exchange_pairs_exchange_index ON public.asset_exchange_pairs USING btree (exchange);


--
-- Name: available_metrics_data_metric_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX available_metrics_data_metric_index ON public.available_metrics_data USING btree (metric);


--
-- Name: blockchain_address_comments_mapping_blockchain_address_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX blockchain_address_comments_mapping_blockchain_address_id_index ON public.blockchain_address_comments_mapping USING btree (blockchain_address_id);


--
-- Name: blockchain_address_comments_mapping_comment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX blockchain_address_comments_mapping_comment_id_index ON public.blockchain_address_comments_mapping USING btree (comment_id);


--
-- Name: blockchain_address_labels_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX blockchain_address_labels_name_index ON public.blockchain_address_labels USING btree (name);


--
-- Name: blockchain_address_user_pairs_labels_blockchain_address_user_pa; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX blockchain_address_user_pairs_labels_blockchain_address_user_pa ON public.blockchain_address_user_pairs_labels USING btree (blockchain_address_user_pair_id, label_id);


--
-- Name: blockchain_address_user_pairs_user_id_blockchain_address_id_ind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX blockchain_address_user_pairs_user_id_blockchain_address_id_ind ON public.blockchain_address_user_pairs USING btree (user_id, blockchain_address_id);


--
-- Name: blockchain_addresses_address_infrastructure_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX blockchain_addresses_address_infrastructure_id_index ON public.blockchain_addresses USING btree (address, infrastructure_id);


--
-- Name: chart_configuration_comments_mapping_chart_configuration_id_ind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chart_configuration_comments_mapping_chart_configuration_id_ind ON public.chart_configuration_comments_mapping USING btree (chart_configuration_id);


--
-- Name: chart_configuration_comments_mapping_comment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX chart_configuration_comments_mapping_comment_id_index ON public.chart_configuration_comments_mapping USING btree (comment_id);


--
-- Name: chart_configurations_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chart_configurations_project_id_index ON public.chart_configurations USING btree (project_id);


--
-- Name: chart_configurations_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chart_configurations_user_id_index ON public.chart_configurations USING btree (user_id);


--
-- Name: chat_messages_chat_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chat_messages_chat_id_index ON public.chat_messages USING btree (chat_id);


--
-- Name: chat_messages_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chat_messages_inserted_at_index ON public.chat_messages USING btree (inserted_at);


--
-- Name: chat_messages_role_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chat_messages_role_index ON public.chat_messages USING btree (role);


--
-- Name: chats_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chats_inserted_at_index ON public.chats USING btree (inserted_at);


--
-- Name: chats_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chats_type_index ON public.chats USING btree (type);


--
-- Name: chats_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chats_user_id_index ON public.chats USING btree (user_id);


--
-- Name: clickhouse_query_executions_query_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX clickhouse_query_executions_query_id_index ON public.clickhouse_query_executions USING btree (query_id);


--
-- Name: contract_addresses_project_id_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contract_addresses_project_id_address_index ON public.contract_addresses USING btree (project_id, address);


--
-- Name: cryptocompare_exporter_progress_key_queue_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cryptocompare_exporter_progress_key_queue_index ON public.cryptocompare_exporter_progress USING btree (key, queue);


--
-- Name: currencies_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX currencies_code_index ON public.currencies USING btree (code);


--
-- Name: dashboard_comments_mapping_comment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dashboard_comments_mapping_comment_id_index ON public.dashboard_comments_mapping USING btree (comment_id);


--
-- Name: dashboard_comments_mapping_dashboard_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_comments_mapping_dashboard_id_index ON public.dashboard_comments_mapping USING btree (dashboard_id);


--
-- Name: dashboard_query_mappings_dashboard_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_query_mappings_dashboard_id_index ON public.dashboard_query_mappings USING btree (dashboard_id);


--
-- Name: dashboard_query_mappings_query_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_query_mappings_query_id_index ON public.dashboard_query_mappings USING btree (query_id);


--
-- Name: dashboards_cache_dashboard_id_parameters_override_hash_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dashboards_cache_dashboard_id_parameters_override_hash_index ON public.dashboards_cache USING btree (dashboard_id, parameters_override_hash);


--
-- Name: dashboards_history_dashboard_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboards_history_dashboard_id_index ON public.dashboards_history USING btree (dashboard_id);


--
-- Name: dashboards_history_hash_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboards_history_hash_index ON public.dashboards_history USING btree (hash);


--
-- Name: discord_dashboards_dashboard_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discord_dashboards_dashboard_id_index ON public.discord_dashboards USING btree (dashboard_id);


--
-- Name: discord_dashboards_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX discord_dashboards_user_id_index ON public.discord_dashboards USING btree (user_id);


--
-- Name: document_tokens_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_tokens_index ON public.posts USING gin (document_tokens);


--
-- Name: ecosystems_ecosystem_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ecosystems_ecosystem_index ON public.ecosystems USING btree (ecosystem);


--
-- Name: email_login_attempts_ip_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX email_login_attempts_ip_address_index ON public.email_login_attempts USING btree (ip_address);


--
-- Name: email_login_attempts_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX email_login_attempts_user_id_index ON public.email_login_attempts USING btree (user_id);


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
-- Name: featured_items_dashboard_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX featured_items_dashboard_id_index ON public.featured_items USING btree (dashboard_id);


--
-- Name: featured_items_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX featured_items_post_id_index ON public.featured_items USING btree (post_id);


--
-- Name: featured_items_query_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX featured_items_query_id_index ON public.featured_items USING btree (query_id);


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
-- Name: finished_oban_jobs_args_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finished_oban_jobs_args_index ON public.finished_oban_jobs USING gin (args);


--
-- Name: finished_oban_jobs_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finished_oban_jobs_inserted_at_index ON public.finished_oban_jobs USING btree (inserted_at);


--
-- Name: finished_oban_jobs_queue_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finished_oban_jobs_queue_index ON public.finished_oban_jobs USING btree (queue);


--
-- Name: free_form_json_storage_key_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX free_form_json_storage_key_index ON public.free_form_json_storage USING btree (key);


--
-- Name: geoip_data_ip_address_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX geoip_data_ip_address_index ON public.geoip_data USING btree (ip_address);


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
-- Name: latest_coinmarketcap_data_coinmarketcap_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX latest_coinmarketcap_data_coinmarketcap_id_index ON public.latest_coinmarketcap_data USING btree (coinmarketcap_id);


--
-- Name: linked_users_candidates_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX linked_users_candidates_token_index ON public.linked_users_candidates USING btree (token);


--
-- Name: linked_users_secondary_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX linked_users_secondary_user_id_index ON public.linked_users USING btree (secondary_user_id);


--
-- Name: list_items_user_list_id_blockchain_address_user_pair_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX list_items_user_list_id_blockchain_address_user_pair_id_index ON public.list_items USING btree (user_list_id, blockchain_address_user_pair_id);


--
-- Name: list_items_user_list_id_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX list_items_user_list_id_project_id_index ON public.list_items USING btree (user_list_id, project_id);


--
-- Name: market_segments_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX market_segments_name_index ON public.market_segments USING btree (name);


--
-- Name: menus_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX menus_user_id_index ON public.menus USING btree (user_id);


--
-- Name: metric_registry_changelog_metric_registry_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX metric_registry_changelog_metric_registry_id_index ON public.metric_registry_changelog USING btree (metric_registry_id);


--
-- Name: metric_registry_composite_unique_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX metric_registry_composite_unique_index ON public.metric_registry USING btree (metric, data_type, fixed_parameters);


--
-- Name: metric_registry_sync_runs_uuid_sync_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX metric_registry_sync_runs_uuid_sync_type_index ON public.metric_registry_sync_runs USING btree (uuid, sync_type);


--
-- Name: metrics_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX metrics_name_index ON public.metrics USING btree (name);


--
-- Name: monitored_twitter_handles_handle_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX monitored_twitter_handles_handle_index ON public.monitored_twitter_handles USING btree (handle);


--
-- Name: notification_templates_action_step_channel_mime_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX notification_templates_action_step_channel_mime_type_index ON public.notification_templates USING btree (action, step, channel, mime_type);


--
-- Name: notification_templates_channel_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_templates_channel_index ON public.notification_templates USING btree (channel);


--
-- Name: notifications_job_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_job_id_index ON public.notifications USING btree (job_id);


--
-- Name: notifications_metric_registry_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_metric_registry_id_index ON public.notifications USING btree (metric_registry_id);


--
-- Name: notifications_notification_template_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_notification_template_id_index ON public.notifications USING btree (notification_template_id);


--
-- Name: notifications_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_status_index ON public.notifications USING btree (status);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON public.oban_jobs USING btree (state, queue, priority, scheduled_at, id);


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
-- Name: post_images_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_images_post_id_index ON public.post_images USING btree (post_id);


--
-- Name: posts_metrics_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_metrics_post_id_index ON public.posts_metrics USING btree (post_id);


--
-- Name: posts_metrics_post_id_metric_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX posts_metrics_post_id_metric_id_index ON public.posts_metrics USING btree (post_id, metric_id);


--
-- Name: posts_projects_post_id_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX posts_projects_post_id_project_id_index ON public.posts_projects USING btree (post_id, project_id);


--
-- Name: posts_tags_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_tags_post_id_index ON public.posts_tags USING btree (post_id);


--
-- Name: presigned_s3_urls_user_id_bucket_object_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX presigned_s3_urls_user_id_bucket_object_index ON public.presigned_s3_urls USING btree (user_id, bucket, object);


--
-- Name: price_scraping_progress_identifier_source_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX price_scraping_progress_identifier_source_index ON public.price_scraping_progress USING btree (identifier, source);


--
-- Name: products_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX products_code_index ON public.products USING btree (code);


--
-- Name: products_stripe_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX products_stripe_id_index ON public.products USING btree (stripe_id);


--
-- Name: project_ecosystem_mappings_project_id_ecosystem_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_ecosystem_mappings_project_id_ecosystem_id_index ON public.project_ecosystem_mappings USING btree (project_id, ecosystem_id);


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
-- Name: pumpkins_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pumpkins_user_id_index ON public.pumpkins USING btree (user_id);


--
-- Name: queries_cache_query_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX queries_cache_query_id_user_id_index ON public.queries_cache USING btree (query_id, user_id);


--
-- Name: queries_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX queries_user_id_index ON public.queries USING btree (user_id);


--
-- Name: questionnaire_answers_question_uuid_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX questionnaire_answers_question_uuid_user_id_index ON public.questionnaire_answers USING btree (question_uuid, user_id);


--
-- Name: san_burn_credit_transactions_trx_hash_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX san_burn_credit_transactions_trx_hash_index ON public.san_burn_credit_transactions USING btree (trx_hash);


--
-- Name: sanr_emails_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sanr_emails_email_index ON public.sanr_emails USING btree (email);


--
-- Name: schedule_rescrape_prices_project_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX schedule_rescrape_prices_project_id_index ON public.schedule_rescrape_prices USING btree (project_id);


--
-- Name: scheduled_deprecation_notifications_deprecation_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scheduled_deprecation_notifications_deprecation_date_index ON public.scheduled_deprecation_notifications USING btree (deprecation_date);


--
-- Name: scheduled_deprecation_notifications_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scheduled_deprecation_notifications_status_index ON public.scheduled_deprecation_notifications USING btree (status);


--
-- Name: seen_timeline_events_user_id_event_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX seen_timeline_events_user_id_event_id_index ON public.seen_timeline_events USING btree (user_id, event_id);


--
-- Name: shared_access_tokens_chart_configuration_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shared_access_tokens_chart_configuration_id_index ON public.shared_access_tokens USING btree (chart_configuration_id);


--
-- Name: shared_access_tokens_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shared_access_tokens_uuid_index ON public.shared_access_tokens USING btree (uuid);


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
-- Name: signals_historical_activity_user_trigger_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX signals_historical_activity_user_trigger_id_index ON public.signals_historical_activity USING btree (user_trigger_id);


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
-- Name: timeline_events_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX timeline_events_inserted_at_index ON public.timeline_events USING btree (inserted_at);


--
-- Name: timeline_events_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX timeline_events_post_id_index ON public.timeline_events USING btree (post_id);


--
-- Name: timeline_events_user_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX timeline_events_user_id_inserted_at_index ON public.timeline_events USING btree (user_id, inserted_at);


--
-- Name: timeline_events_user_list_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX timeline_events_user_list_id_index ON public.timeline_events USING btree (user_list_id);


--
-- Name: timeline_events_user_trigger_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX timeline_events_user_trigger_id_index ON public.timeline_events USING btree (user_trigger_id);


--
-- Name: tweet_predictions_tweet_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX tweet_predictions_tweet_id_index ON public.tweet_predictions USING btree (tweet_id);


--
-- Name: ui_metadata_categories_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ui_metadata_categories_name_index ON public.ui_metadata_categories USING btree (name);


--
-- Name: ui_metadata_groups_name_category_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ui_metadata_groups_name_category_id_index ON public.ui_metadata_groups USING btree (name, category_id);


--
-- Name: user_affiliate_details_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_affiliate_details_user_id_index ON public.user_affiliate_details USING btree (user_id);


--
-- Name: user_api_key_tokens_token_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_api_key_tokens_token_index ON public.user_api_key_tokens USING btree (token);


--
-- Name: user_entity_interactions_entity_type_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_entity_interactions_entity_type_entity_id_index ON public.user_entity_interactions USING btree (entity_type, entity_id);


--
-- Name: user_entity_interactions_entity_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_entity_interactions_entity_type_index ON public.user_entity_interactions USING btree (entity_type);


--
-- Name: user_entity_interactions_interaction_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_entity_interactions_interaction_type_index ON public.user_entity_interactions USING btree (interaction_type);


--
-- Name: user_entity_interactions_user_id_entity_type_entity_id_interact; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_entity_interactions_user_id_entity_type_entity_id_interact ON public.user_entity_interactions USING btree (user_id, entity_type, entity_id, interaction_type, inserted_at);


--
-- Name: user_entity_interactions_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_entity_interactions_user_id_index ON public.user_entity_interactions USING btree (user_id);


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
-- Name: user_lists_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_lists_slug_index ON public.user_lists USING btree (slug);


--
-- Name: user_promo_codes_coupon_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_promo_codes_coupon_index ON public.user_promo_codes USING btree (coupon);


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
-- Name: user_uniswap_staking_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_uniswap_staking_user_id_index ON public.user_uniswap_staking USING btree (user_id);


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
-- Name: users_twitter_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_twitter_id_index ON public.users USING btree (twitter_id);


--
-- Name: users_username_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_username_index ON public.users USING btree (username);


--
-- Name: versions_entity_schema_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX versions_entity_schema_entity_id_index ON public.versions USING btree (entity_schema, entity_id);


--
-- Name: votes_chart_configuration_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_chart_configuration_id_user_id_index ON public.votes USING btree (chart_configuration_id, user_id);


--
-- Name: votes_dashboard_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_dashboard_id_user_id_index ON public.votes USING btree (dashboard_id, user_id);


--
-- Name: votes_post_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX votes_post_id_index ON public.votes USING btree (post_id);


--
-- Name: votes_post_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_post_id_user_id_index ON public.votes USING btree (post_id, user_id);


--
-- Name: votes_query_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_query_id_user_id_index ON public.votes USING btree (query_id, user_id);


--
-- Name: votes_timeline_event_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_timeline_event_id_user_id_index ON public.votes USING btree (timeline_event_id, user_id);


--
-- Name: votes_user_trigger_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_user_trigger_id_user_id_index ON public.votes USING btree (user_trigger_id, user_id);


--
-- Name: votes_watchlist_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX votes_watchlist_id_user_id_index ON public.votes USING btree (watchlist_id, user_id);


--
-- Name: wallet_hunters_bounties_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wallet_hunters_bounties_user_id_index ON public.wallet_hunters_bounties USING btree (user_id);


--
-- Name: wallet_hunters_proposals_comments_mapping_comment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wallet_hunters_proposals_comments_mapping_comment_id_index ON public.wallet_hunters_proposals_comments_mapping USING btree (comment_id);


--
-- Name: wallet_hunters_proposals_comments_mapping_proposal_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wallet_hunters_proposals_comments_mapping_proposal_id_index ON public.wallet_hunters_proposals_comments_mapping USING btree (proposal_id);


--
-- Name: wallet_hunters_proposals_proposal_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wallet_hunters_proposals_proposal_id_index ON public.wallet_hunters_proposals USING btree (proposal_id);


--
-- Name: wallet_hunters_proposals_transaction_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wallet_hunters_proposals_transaction_id_index ON public.wallet_hunters_proposals USING btree (transaction_id);


--
-- Name: wallet_hunters_relays_quota_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wallet_hunters_relays_quota_user_id_index ON public.wallet_hunters_relays_quota USING btree (user_id);


--
-- Name: wallet_hunters_votes_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wallet_hunters_votes_user_id_index ON public.wallet_hunters_votes USING btree (user_id);


--
-- Name: watchlist_comments_mapping_comment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX watchlist_comments_mapping_comment_id_index ON public.watchlist_comments_mapping USING btree (comment_id);


--
-- Name: watchlist_comments_mapping_watchlist_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX watchlist_comments_mapping_watchlist_id_index ON public.watchlist_comments_mapping USING btree (watchlist_id);


--
-- Name: watchlist_settings_watchlist_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX watchlist_settings_watchlist_id_index ON public.watchlist_settings USING btree (watchlist_id);


--
-- Name: webinar_registrations_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX webinar_registrations_user_id_index ON public.webinar_registrations USING btree (user_id);


--
-- Name: webinar_registrations_user_id_webinar_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX webinar_registrations_user_id_webinar_id_index ON public.webinar_registrations USING btree (user_id, webinar_id);


--
-- Name: webinar_registrations_webinar_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX webinar_registrations_webinar_id_index ON public.webinar_registrations USING btree (webinar_id);


--
-- Name: oban_jobs oban_notify; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER oban_notify AFTER INSERT ON public.oban_jobs FOR EACH ROW EXECUTE FUNCTION public.oban_jobs_notify();


--
-- Name: access_attempts access_attempts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_attempts
    ADD CONSTRAINT access_attempts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ai_gen_code ai_gen_code_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_gen_code
    ADD CONSTRAINT ai_gen_code_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.ai_gen_code(id);


--
-- Name: api_call_limits api_call_limits_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_call_limits
    ADD CONSTRAINT api_call_limits_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: blockchain_address_comments_mapping blockchain_address_comments_mapping_blockchain_address_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_comments_mapping
    ADD CONSTRAINT blockchain_address_comments_mapping_blockchain_address_id_fkey FOREIGN KEY (blockchain_address_id) REFERENCES public.blockchain_addresses(id) ON DELETE CASCADE;


--
-- Name: blockchain_address_comments_mapping blockchain_address_comments_mapping_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_comments_mapping
    ADD CONSTRAINT blockchain_address_comments_mapping_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: blockchain_address_user_pairs blockchain_address_user_pairs_blockchain_address_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_user_pairs
    ADD CONSTRAINT blockchain_address_user_pairs_blockchain_address_id_fkey FOREIGN KEY (blockchain_address_id) REFERENCES public.blockchain_addresses(id);


--
-- Name: blockchain_address_user_pairs_labels blockchain_address_user_pairs_labels_blockchain_address_user_pa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_user_pairs_labels
    ADD CONSTRAINT blockchain_address_user_pairs_labels_blockchain_address_user_pa FOREIGN KEY (blockchain_address_user_pair_id) REFERENCES public.blockchain_address_user_pairs(id);


--
-- Name: blockchain_address_user_pairs_labels blockchain_address_user_pairs_labels_label_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_user_pairs_labels
    ADD CONSTRAINT blockchain_address_user_pairs_labels_label_id_fkey FOREIGN KEY (label_id) REFERENCES public.blockchain_address_labels(id);


--
-- Name: blockchain_address_user_pairs blockchain_address_user_pairs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_address_user_pairs
    ADD CONSTRAINT blockchain_address_user_pairs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: blockchain_addresses blockchain_addresses_infrastructure_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blockchain_addresses
    ADD CONSTRAINT blockchain_addresses_infrastructure_id_fkey FOREIGN KEY (infrastructure_id) REFERENCES public.infrastructures(id);


--
-- Name: chart_configuration_comments_mapping chart_configuration_comments_mapping_chart_configuration_id_fke; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configuration_comments_mapping
    ADD CONSTRAINT chart_configuration_comments_mapping_chart_configuration_id_fke FOREIGN KEY (chart_configuration_id) REFERENCES public.chart_configurations(id) ON DELETE CASCADE;


--
-- Name: chart_configuration_comments_mapping chart_configuration_comments_mapping_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chart_configuration_comments_mapping
    ADD CONSTRAINT chart_configuration_comments_mapping_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE CASCADE;


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
-- Name: chat_messages chat_messages_chat_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_chat_id_fkey FOREIGN KEY (chat_id) REFERENCES public.chats(id) ON DELETE CASCADE;


--
-- Name: chats chats_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT chats_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: clickhouse_query_executions clickhouse_query_executions_query_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clickhouse_query_executions
    ADD CONSTRAINT clickhouse_query_executions_query_id_fkey FOREIGN KEY (query_id) REFERENCES public.queries(id) ON DELETE SET NULL;


--
-- Name: clickhouse_query_executions clickhouse_query_executions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clickhouse_query_executions
    ADD CONSTRAINT clickhouse_query_executions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


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
-- Name: dashboard_comments_mapping dashboard_comments_mapping_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_comments_mapping
    ADD CONSTRAINT dashboard_comments_mapping_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: dashboard_comments_mapping dashboard_comments_mapping_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_comments_mapping
    ADD CONSTRAINT dashboard_comments_mapping_dashboard_id_fkey FOREIGN KEY (dashboard_id) REFERENCES public.dashboards(id) ON DELETE CASCADE;


--
-- Name: dashboard_query_mappings dashboard_query_mappings_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_query_mappings
    ADD CONSTRAINT dashboard_query_mappings_dashboard_id_fkey FOREIGN KEY (dashboard_id) REFERENCES public.dashboards(id) ON DELETE CASCADE;


--
-- Name: dashboard_query_mappings dashboard_query_mappings_query_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_query_mappings
    ADD CONSTRAINT dashboard_query_mappings_query_id_fkey FOREIGN KEY (query_id) REFERENCES public.queries(id) ON DELETE CASCADE;


--
-- Name: dashboards_cache dashboards_cache_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards_cache
    ADD CONSTRAINT dashboards_cache_dashboard_id_fkey FOREIGN KEY (dashboard_id) REFERENCES public.dashboards(id) ON DELETE CASCADE;


--
-- Name: dashboards_history dashboards_history_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards_history
    ADD CONSTRAINT dashboards_history_dashboard_id_fkey FOREIGN KEY (dashboard_id) REFERENCES public.dashboards(id);


--
-- Name: dashboards_history dashboards_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards_history
    ADD CONSTRAINT dashboards_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: dashboards dashboards_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboards
    ADD CONSTRAINT dashboards_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: discord_dashboards discord_dashboards_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discord_dashboards
    ADD CONSTRAINT discord_dashboards_dashboard_id_fkey FOREIGN KEY (dashboard_id) REFERENCES public.dashboards(id);


--
-- Name: discord_dashboards discord_dashboards_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discord_dashboards
    ADD CONSTRAINT discord_dashboards_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: email_login_attempts email_login_attempts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_login_attempts
    ADD CONSTRAINT email_login_attempts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


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
    ADD CONSTRAINT featured_items_chart_configuration_id_fkey FOREIGN KEY (chart_configuration_id) REFERENCES public.chart_configurations(id) ON DELETE CASCADE;


--
-- Name: featured_items featured_items_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_dashboard_id_fkey FOREIGN KEY (dashboard_id) REFERENCES public.dashboards(id);


--
-- Name: featured_items featured_items_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: featured_items featured_items_query_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_query_id_fkey FOREIGN KEY (query_id) REFERENCES public.queries(id);


--
-- Name: featured_items featured_items_table_configuration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_table_configuration_id_fkey FOREIGN KEY (table_configuration_id) REFERENCES public.table_configurations(id) ON DELETE CASCADE;


--
-- Name: featured_items featured_items_user_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_user_list_id_fkey FOREIGN KEY (user_list_id) REFERENCES public.user_lists(id) ON DELETE CASCADE;


--
-- Name: featured_items featured_items_user_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.featured_items
    ADD CONSTRAINT featured_items_user_trigger_id_fkey FOREIGN KEY (user_trigger_id) REFERENCES public.user_triggers(id) ON DELETE CASCADE;


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
-- Name: linked_users_candidates linked_users_candidates_primary_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linked_users_candidates
    ADD CONSTRAINT linked_users_candidates_primary_user_id_fkey FOREIGN KEY (primary_user_id) REFERENCES public.users(id);


--
-- Name: linked_users_candidates linked_users_candidates_secondary_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linked_users_candidates
    ADD CONSTRAINT linked_users_candidates_secondary_user_id_fkey FOREIGN KEY (secondary_user_id) REFERENCES public.users(id);


--
-- Name: linked_users linked_users_primary_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linked_users
    ADD CONSTRAINT linked_users_primary_user_id_fkey FOREIGN KEY (primary_user_id) REFERENCES public.users(id);


--
-- Name: linked_users linked_users_secondary_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.linked_users
    ADD CONSTRAINT linked_users_secondary_user_id_fkey FOREIGN KEY (secondary_user_id) REFERENCES public.users(id);


--
-- Name: list_items list_items_blockchain_address_user_pair_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT list_items_blockchain_address_user_pair_id_fkey FOREIGN KEY (blockchain_address_user_pair_id) REFERENCES public.blockchain_address_user_pairs(id);


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
-- Name: menu_items menu_items_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_dashboard_id_fkey FOREIGN KEY (dashboard_id) REFERENCES public.dashboards(id) ON DELETE CASCADE;


--
-- Name: menu_items menu_items_menu_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_menu_id_fkey FOREIGN KEY (menu_id) REFERENCES public.menus(id) ON DELETE CASCADE;


--
-- Name: menu_items menu_items_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.menus(id) ON DELETE CASCADE;


--
-- Name: menu_items menu_items_query_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_query_id_fkey FOREIGN KEY (query_id) REFERENCES public.queries(id) ON DELETE CASCADE;


--
-- Name: menus menus_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menus
    ADD CONSTRAINT menus_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.menus(id) ON DELETE CASCADE;


--
-- Name: menus menus_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menus
    ADD CONSTRAINT menus_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: metric_display_order metric_display_order_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_display_order
    ADD CONSTRAINT metric_display_order_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.ui_metadata_categories(id) ON DELETE CASCADE;


--
-- Name: metric_display_order metric_display_order_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_display_order
    ADD CONSTRAINT metric_display_order_group_id_fkey FOREIGN KEY (group_id) REFERENCES public.ui_metadata_groups(id) ON DELETE CASCADE;


--
-- Name: metric_display_order metric_display_order_metric_registry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_display_order
    ADD CONSTRAINT metric_display_order_metric_registry_id_fkey FOREIGN KEY (metric_registry_id) REFERENCES public.metric_registry(id) ON DELETE CASCADE;


--
-- Name: metric_registry_change_suggestions metric_registry_change_suggestions_metric_registry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_registry_change_suggestions
    ADD CONSTRAINT metric_registry_change_suggestions_metric_registry_id_fkey FOREIGN KEY (metric_registry_id) REFERENCES public.metric_registry(id) ON DELETE CASCADE;


--
-- Name: metric_registry_changelog metric_registry_changelog_metric_registry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_registry_changelog
    ADD CONSTRAINT metric_registry_changelog_metric_registry_id_fkey FOREIGN KEY (metric_registry_id) REFERENCES public.metric_registry(id);


--
-- Name: monitored_twitter_handles monitored_twitter_handles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monitored_twitter_handles
    ADD CONSTRAINT monitored_twitter_handles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: notifications notifications_metric_registry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_metric_registry_id_fkey FOREIGN KEY (metric_registry_id) REFERENCES public.metric_registry(id);


--
-- Name: notifications notifications_notification_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_notification_template_id_fkey FOREIGN KEY (notification_template_id) REFERENCES public.notification_templates(id);


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
    ADD CONSTRAINT posts_metrics_metric_id_fkey FOREIGN KEY (metric_id) REFERENCES public.metrics(id) ON DELETE CASCADE;


--
-- Name: posts_metrics posts_metrics_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_metrics
    ADD CONSTRAINT posts_metrics_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


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
    ADD CONSTRAINT posts_tags_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: posts_tags posts_tags_tag_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts_tags
    ADD CONSTRAINT posts_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id) ON DELETE CASCADE;


--
-- Name: posts posts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: presigned_s3_urls presigned_s3_urls_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presigned_s3_urls
    ADD CONSTRAINT presigned_s3_urls_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: project project_deployed_on_ecosystem_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT project_deployed_on_ecosystem_id_fkey FOREIGN KEY (deployed_on_ecosystem_id) REFERENCES public.ecosystems(id);


--
-- Name: project_ecosystem_labels_change_suggestions project_ecosystem_labels_change_suggestions_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_ecosystem_labels_change_suggestions
    ADD CONSTRAINT project_ecosystem_labels_change_suggestions_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: project_ecosystem_mappings project_ecosystem_mappings_ecosystem_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_ecosystem_mappings
    ADD CONSTRAINT project_ecosystem_mappings_ecosystem_id_fkey FOREIGN KEY (ecosystem_id) REFERENCES public.ecosystems(id);


--
-- Name: project_ecosystem_mappings project_ecosystem_mappings_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_ecosystem_mappings
    ADD CONSTRAINT project_ecosystem_mappings_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: project_eth_address project_eth_address_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_eth_address
    ADD CONSTRAINT project_eth_address_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: project_github_organizations_change_suggestions project_github_organizations_change_suggestions_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_github_organizations_change_suggestions
    ADD CONSTRAINT project_github_organizations_change_suggestions_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


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
-- Name: pumpkins pumpkins_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pumpkins
    ADD CONSTRAINT pumpkins_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: queries_cache queries_cache_query_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queries_cache
    ADD CONSTRAINT queries_cache_query_id_fkey FOREIGN KEY (query_id) REFERENCES public.queries(id) ON DELETE CASCADE;


--
-- Name: queries_cache queries_cache_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queries_cache
    ADD CONSTRAINT queries_cache_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: queries queries_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queries
    ADD CONSTRAINT queries_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: questionnaire_answers questionnaire_answers_question_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_answers
    ADD CONSTRAINT questionnaire_answers_question_uuid_fkey FOREIGN KEY (question_uuid) REFERENCES public.questionnaire_questions(uuid) ON DELETE CASCADE;


--
-- Name: questionnaire_answers questionnaire_answers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_answers
    ADD CONSTRAINT questionnaire_answers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: questionnaire_questions questionnaire_questions_questionnaire_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_questions
    ADD CONSTRAINT questionnaire_questions_questionnaire_uuid_fkey FOREIGN KEY (questionnaire_uuid) REFERENCES public.questionnaires(uuid) ON DELETE CASCADE;


--
-- Name: san_burn_credit_transactions san_burn_credit_transactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.san_burn_credit_transactions
    ADD CONSTRAINT san_burn_credit_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: schedule_rescrape_prices schedule_rescrape_prices_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_rescrape_prices
    ADD CONSTRAINT schedule_rescrape_prices_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id);


--
-- Name: seen_timeline_events seen_timeline_events_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seen_timeline_events
    ADD CONSTRAINT seen_timeline_events_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.timeline_events(id);


--
-- Name: seen_timeline_events seen_timeline_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seen_timeline_events
    ADD CONSTRAINT seen_timeline_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: shared_access_tokens shared_access_tokens_chart_configuration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shared_access_tokens
    ADD CONSTRAINT shared_access_tokens_chart_configuration_id_fkey FOREIGN KEY (chart_configuration_id) REFERENCES public.chart_configurations(id);


--
-- Name: shared_access_tokens shared_access_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shared_access_tokens
    ADD CONSTRAINT shared_access_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


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
    ADD CONSTRAINT signals_historical_activity_user_trigger_id_fkey FOREIGN KEY (user_trigger_id) REFERENCES public.user_triggers(id) ON DELETE CASCADE;


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
    ADD CONSTRAINT timeline_events_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: timeline_events timeline_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events
    ADD CONSTRAINT timeline_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: timeline_events timeline_events_user_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events
    ADD CONSTRAINT timeline_events_user_list_id_fkey FOREIGN KEY (user_list_id) REFERENCES public.user_lists(id) ON DELETE CASCADE;


--
-- Name: timeline_events timeline_events_user_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.timeline_events
    ADD CONSTRAINT timeline_events_user_trigger_id_fkey FOREIGN KEY (user_trigger_id) REFERENCES public.user_triggers(id) ON DELETE CASCADE;


--
-- Name: ui_metadata_groups ui_metadata_groups_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ui_metadata_groups
    ADD CONSTRAINT ui_metadata_groups_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.ui_metadata_categories(id) ON DELETE CASCADE;


--
-- Name: user_affiliate_details user_affiliate_details_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_affiliate_details
    ADD CONSTRAINT user_affiliate_details_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_api_key_tokens user_api_key_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_api_key_tokens
    ADD CONSTRAINT user_api_key_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_entity_interactions user_entity_interactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_entity_interactions
    ADD CONSTRAINT user_entity_interactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


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
-- Name: user_lists user_lists_table_configuration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lists
    ADD CONSTRAINT user_lists_table_configuration_id_fkey FOREIGN KEY (table_configuration_id) REFERENCES public.table_configurations(id) ON DELETE SET NULL;


--
-- Name: user_lists user_lists_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_lists
    ADD CONSTRAINT user_lists_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_promo_codes user_promo_codes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_promo_codes
    ADD CONSTRAINT user_promo_codes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


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
-- Name: user_uniswap_staking user_uniswap_staking_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_uniswap_staking
    ADD CONSTRAINT user_uniswap_staking_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: versions versions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: votes votes_chart_configuration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_chart_configuration_id_fkey FOREIGN KEY (chart_configuration_id) REFERENCES public.chart_configurations(id) ON DELETE CASCADE;


--
-- Name: votes votes_dashboard_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_dashboard_id_fkey FOREIGN KEY (dashboard_id) REFERENCES public.dashboards(id);


--
-- Name: votes votes_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: votes votes_query_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_query_id_fkey FOREIGN KEY (query_id) REFERENCES public.queries(id);


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
-- Name: votes votes_user_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_user_trigger_id_fkey FOREIGN KEY (user_trigger_id) REFERENCES public.user_triggers(id) ON DELETE CASCADE;


--
-- Name: votes votes_watchlist_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_watchlist_id_fkey FOREIGN KEY (watchlist_id) REFERENCES public.user_lists(id) ON DELETE CASCADE;


--
-- Name: wallet_hunters_bounties wallet_hunters_bounties_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_bounties
    ADD CONSTRAINT wallet_hunters_bounties_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: wallet_hunters_proposals wallet_hunters_proposals_bounty_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_proposals
    ADD CONSTRAINT wallet_hunters_proposals_bounty_id_fkey FOREIGN KEY (bounty_id) REFERENCES public.wallet_hunters_bounties(id) ON DELETE CASCADE;


--
-- Name: wallet_hunters_proposals_comments_mapping wallet_hunters_proposals_comments_mapping_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_proposals_comments_mapping
    ADD CONSTRAINT wallet_hunters_proposals_comments_mapping_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: wallet_hunters_proposals_comments_mapping wallet_hunters_proposals_comments_mapping_proposal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_proposals_comments_mapping
    ADD CONSTRAINT wallet_hunters_proposals_comments_mapping_proposal_id_fkey FOREIGN KEY (proposal_id) REFERENCES public.wallet_hunters_proposals(id) ON DELETE CASCADE;


--
-- Name: wallet_hunters_proposals wallet_hunters_proposals_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_proposals
    ADD CONSTRAINT wallet_hunters_proposals_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: wallet_hunters_relays_quota wallet_hunters_relays_quota_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_relays_quota
    ADD CONSTRAINT wallet_hunters_relays_quota_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: wallet_hunters_votes wallet_hunters_votes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_hunters_votes
    ADD CONSTRAINT wallet_hunters_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: watchlist_comments_mapping watchlist_comments_mapping_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watchlist_comments_mapping
    ADD CONSTRAINT watchlist_comments_mapping_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: watchlist_comments_mapping watchlist_comments_mapping_watchlist_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watchlist_comments_mapping
    ADD CONSTRAINT watchlist_comments_mapping_watchlist_id_fkey FOREIGN KEY (watchlist_id) REFERENCES public.user_lists(id) ON DELETE CASCADE;


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
-- Name: webinar_registrations webinar_registrations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webinar_registrations
    ADD CONSTRAINT webinar_registrations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: webinar_registrations webinar_registrations_webinar_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webinar_registrations
    ADD CONSTRAINT webinar_registrations_webinar_id_fkey FOREIGN KEY (webinar_id) REFERENCES public.webinars(id) ON DELETE CASCADE;


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
INSERT INTO public."schema_migrations" (version) VALUES (20200923090710);
INSERT INTO public."schema_migrations" (version) VALUES (20201016091443);
INSERT INTO public."schema_migrations" (version) VALUES (20201016105225);
INSERT INTO public."schema_migrations" (version) VALUES (20201016124426);
INSERT INTO public."schema_migrations" (version) VALUES (20201021132548);
INSERT INTO public."schema_migrations" (version) VALUES (20201102120842);
INSERT INTO public."schema_migrations" (version) VALUES (20201109091755);
INSERT INTO public."schema_migrations" (version) VALUES (20201109092655);
INSERT INTO public."schema_migrations" (version) VALUES (20201109112004);
INSERT INTO public."schema_migrations" (version) VALUES (20201109124013);
INSERT INTO public."schema_migrations" (version) VALUES (20201110115647);
INSERT INTO public."schema_migrations" (version) VALUES (20201112142519);
INSERT INTO public."schema_migrations" (version) VALUES (20201113114758);
INSERT INTO public."schema_migrations" (version) VALUES (20201116091112);
INSERT INTO public."schema_migrations" (version) VALUES (20201117123908);
INSERT INTO public."schema_migrations" (version) VALUES (20201117132755);
INSERT INTO public."schema_migrations" (version) VALUES (20201118125118);
INSERT INTO public."schema_migrations" (version) VALUES (20201118141407);
INSERT INTO public."schema_migrations" (version) VALUES (20201118145315);
INSERT INTO public."schema_migrations" (version) VALUES (20201119085940);
INSERT INTO public."schema_migrations" (version) VALUES (20201201102246);
INSERT INTO public."schema_migrations" (version) VALUES (20201202125900);
INSERT INTO public."schema_migrations" (version) VALUES (20210115081700);
INSERT INTO public."schema_migrations" (version) VALUES (20210118080213);
INSERT INTO public."schema_migrations" (version) VALUES (20210119085344);
INSERT INTO public."schema_migrations" (version) VALUES (20210120090715);
INSERT INTO public."schema_migrations" (version) VALUES (20210128140807);
INSERT INTO public."schema_migrations" (version) VALUES (20210201105522);
INSERT INTO public."schema_migrations" (version) VALUES (20210202161636);
INSERT INTO public."schema_migrations" (version) VALUES (20210205121406);
INSERT INTO public."schema_migrations" (version) VALUES (20210209085710);
INSERT INTO public."schema_migrations" (version) VALUES (20210222141227);
INSERT INTO public."schema_migrations" (version) VALUES (20210223081041);
INSERT INTO public."schema_migrations" (version) VALUES (20210226144252);
INSERT INTO public."schema_migrations" (version) VALUES (20210303094304);
INSERT INTO public."schema_migrations" (version) VALUES (20210311123253);
INSERT INTO public."schema_migrations" (version) VALUES (20210323125906);
INSERT INTO public."schema_migrations" (version) VALUES (20210330100652);
INSERT INTO public."schema_migrations" (version) VALUES (20210406104622);
INSERT INTO public."schema_migrations" (version) VALUES (20210406113235);
INSERT INTO public."schema_migrations" (version) VALUES (20210408103523);
INSERT INTO public."schema_migrations" (version) VALUES (20210408131830);
INSERT INTO public."schema_migrations" (version) VALUES (20210409081625);
INSERT INTO public."schema_migrations" (version) VALUES (20210413091357);
INSERT INTO public."schema_migrations" (version) VALUES (20210416074600);
INSERT INTO public."schema_migrations" (version) VALUES (20210416132337);
INSERT INTO public."schema_migrations" (version) VALUES (20210419130213);
INSERT INTO public."schema_migrations" (version) VALUES (20210419183855);
INSERT INTO public."schema_migrations" (version) VALUES (20210419190728);
INSERT INTO public."schema_migrations" (version) VALUES (20210420120610);
INSERT INTO public."schema_migrations" (version) VALUES (20210513102007);
INSERT INTO public."schema_migrations" (version) VALUES (20210518083003);
INSERT INTO public."schema_migrations" (version) VALUES (20210604163821);
INSERT INTO public."schema_migrations" (version) VALUES (20210608133141);
INSERT INTO public."schema_migrations" (version) VALUES (20210609082745);
INSERT INTO public."schema_migrations" (version) VALUES (20210616123403);
INSERT INTO public."schema_migrations" (version) VALUES (20210701130227);
INSERT INTO public."schema_migrations" (version) VALUES (20210705104243);
INSERT INTO public."schema_migrations" (version) VALUES (20210707135227);
INSERT INTO public."schema_migrations" (version) VALUES (20210708111602);
INSERT INTO public."schema_migrations" (version) VALUES (20210712125345);
INSERT INTO public."schema_migrations" (version) VALUES (20210716075649);
INSERT INTO public."schema_migrations" (version) VALUES (20210721140912);
INSERT INTO public."schema_migrations" (version) VALUES (20210722141655);
INSERT INTO public."schema_migrations" (version) VALUES (20210727124520);
INSERT INTO public."schema_migrations" (version) VALUES (20210727124524);
INSERT INTO public."schema_migrations" (version) VALUES (20210728101938);
INSERT INTO public."schema_migrations" (version) VALUES (20210803092012);
INSERT INTO public."schema_migrations" (version) VALUES (20210816150914);
INSERT INTO public."schema_migrations" (version) VALUES (20210907104846);
INSERT INTO public."schema_migrations" (version) VALUES (20210907104919);
INSERT INTO public."schema_migrations" (version) VALUES (20210921100450);
INSERT INTO public."schema_migrations" (version) VALUES (20211109131726);
INSERT INTO public."schema_migrations" (version) VALUES (20211117104935);
INSERT INTO public."schema_migrations" (version) VALUES (20211124075928);
INSERT INTO public."schema_migrations" (version) VALUES (20211126144929);
INSERT INTO public."schema_migrations" (version) VALUES (20211206104913);
INSERT INTO public."schema_migrations" (version) VALUES (20220201122953);
INSERT INTO public."schema_migrations" (version) VALUES (20220330100631);
INSERT INTO public."schema_migrations" (version) VALUES (20220404132445);
INSERT INTO public."schema_migrations" (version) VALUES (20220413130352);
INSERT INTO public."schema_migrations" (version) VALUES (20220504082527);
INSERT INTO public."schema_migrations" (version) VALUES (20220516082857);
INSERT INTO public."schema_migrations" (version) VALUES (20220519083249);
INSERT INTO public."schema_migrations" (version) VALUES (20220519135027);
INSERT INTO public."schema_migrations" (version) VALUES (20220531133311);
INSERT INTO public."schema_migrations" (version) VALUES (20220531143545);
INSERT INTO public."schema_migrations" (version) VALUES (20220614091809);
INSERT INTO public."schema_migrations" (version) VALUES (20220615120713);
INSERT INTO public."schema_migrations" (version) VALUES (20220615121150);
INSERT INTO public."schema_migrations" (version) VALUES (20220615122849);
INSERT INTO public."schema_migrations" (version) VALUES (20220615135946);
INSERT INTO public."schema_migrations" (version) VALUES (20220616131454);
INSERT INTO public."schema_migrations" (version) VALUES (20220617112317);
INSERT INTO public."schema_migrations" (version) VALUES (20220620132733);
INSERT INTO public."schema_migrations" (version) VALUES (20220620143734);
INSERT INTO public."schema_migrations" (version) VALUES (20220627144857);
INSERT INTO public."schema_migrations" (version) VALUES (20220630123257);
INSERT INTO public."schema_migrations" (version) VALUES (20220712122954);
INSERT INTO public."schema_migrations" (version) VALUES (20220718125615);
INSERT INTO public."schema_migrations" (version) VALUES (20220727072726);
INSERT INTO public."schema_migrations" (version) VALUES (20220804105452);
INSERT INTO public."schema_migrations" (version) VALUES (20220825071308);
INSERT INTO public."schema_migrations" (version) VALUES (20220830115029);
INSERT INTO public."schema_migrations" (version) VALUES (20221025154013);
INSERT INTO public."schema_migrations" (version) VALUES (20221027125500);
INSERT INTO public."schema_migrations" (version) VALUES (20221103145206);
INSERT INTO public."schema_migrations" (version) VALUES (20221110142211);
INSERT INTO public."schema_migrations" (version) VALUES (20221118110940);
INSERT INTO public."schema_migrations" (version) VALUES (20221129102156);
INSERT INTO public."schema_migrations" (version) VALUES (20221212124926);
INSERT INTO public."schema_migrations" (version) VALUES (20221213105305);
INSERT INTO public."schema_migrations" (version) VALUES (20221214090723);
INSERT INTO public."schema_migrations" (version) VALUES (20221215103058);
INSERT INTO public."schema_migrations" (version) VALUES (20221216095648);
INSERT INTO public."schema_migrations" (version) VALUES (20221221113902);
INSERT INTO public."schema_migrations" (version) VALUES (20230113134151);
INSERT INTO public."schema_migrations" (version) VALUES (20230114134332);
INSERT INTO public."schema_migrations" (version) VALUES (20230120101611);
INSERT INTO public."schema_migrations" (version) VALUES (20230124105934);
INSERT INTO public."schema_migrations" (version) VALUES (20230206085439);
INSERT INTO public."schema_migrations" (version) VALUES (20230206100629);
INSERT INTO public."schema_migrations" (version) VALUES (20230210145707);
INSERT INTO public."schema_migrations" (version) VALUES (20230216145219);
INSERT INTO public."schema_migrations" (version) VALUES (20230224120026);
INSERT INTO public."schema_migrations" (version) VALUES (20230327194228);
INSERT INTO public."schema_migrations" (version) VALUES (20230516090551);
INSERT INTO public."schema_migrations" (version) VALUES (20230516091348);
INSERT INTO public."schema_migrations" (version) VALUES (20230519090827);
INSERT INTO public."schema_migrations" (version) VALUES (20230522123937);
INSERT INTO public."schema_migrations" (version) VALUES (20230523080400);
INSERT INTO public."schema_migrations" (version) VALUES (20230526092048);
INSERT INTO public."schema_migrations" (version) VALUES (20230608132801);
INSERT INTO public."schema_migrations" (version) VALUES (20230616110252);
INSERT INTO public."schema_migrations" (version) VALUES (20230626080554);
INSERT INTO public."schema_migrations" (version) VALUES (20230713112639);
INSERT INTO public."schema_migrations" (version) VALUES (20230803140335);
INSERT INTO public."schema_migrations" (version) VALUES (20230810121200);
INSERT INTO public."schema_migrations" (version) VALUES (20230829111631);
INSERT INTO public."schema_migrations" (version) VALUES (20230904092357);
INSERT INTO public."schema_migrations" (version) VALUES (20230904141409);
INSERT INTO public."schema_migrations" (version) VALUES (20230908085236);
INSERT INTO public."schema_migrations" (version) VALUES (20230915121540);
INSERT INTO public."schema_migrations" (version) VALUES (20230925041216);
INSERT INTO public."schema_migrations" (version) VALUES (20231003070443);
INSERT INTO public."schema_migrations" (version) VALUES (20231012122039);
INSERT INTO public."schema_migrations" (version) VALUES (20231012130814);
INSERT INTO public."schema_migrations" (version) VALUES (20231019111320);
INSERT INTO public."schema_migrations" (version) VALUES (20231023123140);
INSERT INTO public."schema_migrations" (version) VALUES (20231026084628);
INSERT INTO public."schema_migrations" (version) VALUES (20231101104145);
INSERT INTO public."schema_migrations" (version) VALUES (20231110093800);
INSERT INTO public."schema_migrations" (version) VALUES (20231206123012);
INSERT INTO public."schema_migrations" (version) VALUES (20231211133112);
INSERT INTO public."schema_migrations" (version) VALUES (20231213100958);
INSERT INTO public."schema_migrations" (version) VALUES (20231213101042);
INSERT INTO public."schema_migrations" (version) VALUES (20240115140319);
INSERT INTO public."schema_migrations" (version) VALUES (20240123102455);
INSERT INTO public."schema_migrations" (version) VALUES (20240123102628);
INSERT INTO public."schema_migrations" (version) VALUES (20240125095156);
INSERT INTO public."schema_migrations" (version) VALUES (20240125141406);
INSERT INTO public."schema_migrations" (version) VALUES (20240126133441);
INSERT INTO public."schema_migrations" (version) VALUES (20240131160724);
INSERT INTO public."schema_migrations" (version) VALUES (20240201085929);
INSERT INTO public."schema_migrations" (version) VALUES (20240212141517);
INSERT INTO public."schema_migrations" (version) VALUES (20240311143940);
INSERT INTO public."schema_migrations" (version) VALUES (20240315090002);
INSERT INTO public."schema_migrations" (version) VALUES (20240320090413);
INSERT INTO public."schema_migrations" (version) VALUES (20240325154734);
INSERT INTO public."schema_migrations" (version) VALUES (20240415100155);
INSERT INTO public."schema_migrations" (version) VALUES (20240424082842);
INSERT INTO public."schema_migrations" (version) VALUES (20240531121027);
INSERT INTO public."schema_migrations" (version) VALUES (20240723122118);
INSERT INTO public."schema_migrations" (version) VALUES (20240725122924);
INSERT INTO public."schema_migrations" (version) VALUES (20240805115620);
INSERT INTO public."schema_migrations" (version) VALUES (20240809122904);
INSERT INTO public."schema_migrations" (version) VALUES (20240904135651);
INSERT INTO public."schema_migrations" (version) VALUES (20240926130910);
INSERT INTO public."schema_migrations" (version) VALUES (20240926135951);
INSERT INTO public."schema_migrations" (version) VALUES (20241017092520);
INSERT INTO public."schema_migrations" (version) VALUES (20241018073651);
INSERT INTO public."schema_migrations" (version) VALUES (20241018075640);
INSERT INTO public."schema_migrations" (version) VALUES (20241029080754);
INSERT INTO public."schema_migrations" (version) VALUES (20241029082533);
INSERT INTO public."schema_migrations" (version) VALUES (20241029151959);
INSERT INTO public."schema_migrations" (version) VALUES (20241030141825);
INSERT INTO public."schema_migrations" (version) VALUES (20241104061632);
INSERT INTO public."schema_migrations" (version) VALUES (20241104115340);
INSERT INTO public."schema_migrations" (version) VALUES (20241108112754);
INSERT INTO public."schema_migrations" (version) VALUES (20241112094924);
INSERT INTO public."schema_migrations" (version) VALUES (20241114140339);
INSERT INTO public."schema_migrations" (version) VALUES (20241114141110);
INSERT INTO public."schema_migrations" (version) VALUES (20241116104556);
INSERT INTO public."schema_migrations" (version) VALUES (20241128113958);
INSERT INTO public."schema_migrations" (version) VALUES (20241128161315);
INSERT INTO public."schema_migrations" (version) VALUES (20241202104812);
INSERT INTO public."schema_migrations" (version) VALUES (20241212054904);
INSERT INTO public."schema_migrations" (version) VALUES (20250110083203);
INSERT INTO public."schema_migrations" (version) VALUES (20250117000001);
INSERT INTO public."schema_migrations" (version) VALUES (20250121155544);
INSERT INTO public."schema_migrations" (version) VALUES (20250203104426);
INSERT INTO public."schema_migrations" (version) VALUES (20250207100755);
INSERT INTO public."schema_migrations" (version) VALUES (20250207134446);
INSERT INTO public."schema_migrations" (version) VALUES (20250207134654);
INSERT INTO public."schema_migrations" (version) VALUES (20250219075723);
INSERT INTO public."schema_migrations" (version) VALUES (20250219155459);
INSERT INTO public."schema_migrations" (version) VALUES (20250220134051);
INSERT INTO public."schema_migrations" (version) VALUES (20250226111103);
INSERT INTO public."schema_migrations" (version) VALUES (20250312085101);
INSERT INTO public."schema_migrations" (version) VALUES (20250313103159);
INSERT INTO public."schema_migrations" (version) VALUES (20250318100855);
INSERT INTO public."schema_migrations" (version) VALUES (20250318100856);
INSERT INTO public."schema_migrations" (version) VALUES (20250324103930);
INSERT INTO public."schema_migrations" (version) VALUES (20250326110304);
INSERT INTO public."schema_migrations" (version) VALUES (20250327120623);
INSERT INTO public."schema_migrations" (version) VALUES (20250411143236);
INSERT INTO public."schema_migrations" (version) VALUES (20250413084531);
INSERT INTO public."schema_migrations" (version) VALUES (20250414115309);
INSERT INTO public."schema_migrations" (version) VALUES (20250414122835);
INSERT INTO public."schema_migrations" (version) VALUES (20250416132314);
INSERT INTO public."schema_migrations" (version) VALUES (20250507135031);
INSERT INTO public."schema_migrations" (version) VALUES (20250512124853);
INSERT INTO public."schema_migrations" (version) VALUES (20250512130838);
INSERT INTO public."schema_migrations" (version) VALUES (20250512140823);
INSERT INTO public."schema_migrations" (version) VALUES (20250512141238);
INSERT INTO public."schema_migrations" (version) VALUES (20250604072648);
