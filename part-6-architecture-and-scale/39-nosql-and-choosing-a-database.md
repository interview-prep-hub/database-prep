# 39. NoSQL and Choosing a Database

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 38](38-sharding-and-distributed-databases.md)

> **In one line:** Choose a datastore from its access patterns, starting with a relational database, and add others only for a clear reason.

## What you will learn

- How to choose a datastore
- Cassandra, DynamoDB and MongoDB modeling
- Caching patterns, and how they fail
- Warehouses, lakes and HTAP
- Serverless databases
- Vector search

## How to choose

**SQL or NoSQL for this workload? Justify it from the access patterns.** Start from data volume, read and write ratio, query shapes, consistency needs and team skills. Relational is the default.

| Family | Good at | Example |
|---|---|---|
| **Key-value** | Fast lookup by key | Redis, DynamoDB |
| **Document** | Whole records with varying shape | MongoDB |
| **Wide-column** | Huge writes on known queries | Cassandra |
| **Graph** | Many-hop relationships | Neo4j |
| **Search** | Full-text relevance | Elasticsearch |
| **Time-series** | Metrics over time | TimescaleDB |
| **Vector** | Similarity | pgvector |

**Schema-on-write vs schema-on-read.** "Schemaless" moves the schema into the application.

**Why do many NoSQL stores write fast?** The LSM tree: writes go to memory and a sequential log ([Chapter 29](../part-5-internals-and-performance/29-indexes.md)).

**PostgreSQL as a multi-tool.** JSONB, full-text search, pgvector, and queues with `FOR UPDATE SKIP LOCKED` may mean you need no extra system.

## Cassandra

**Design one table per query,** with no joins or foreign keys. The **partition key** decides the node, and **clustering columns** sort within a partition.

**Model chat messages in Cassandra. What is the partition key, and why do you need a time bucket?**

```text
PRIMARY KEY ((room_id, day_bucket), message_id)
WITH CLUSTERING ORDER BY (message_id DESC)
```

Partition by room and time bucket, and cluster by time descending. Without the bucket, a busy room's partition grows forever, which breaks reads and repairs.

## DynamoDB

Items have a **partition key** and a **sort key**.

**What is a hot partition in DynamoDB, and how do you fix it?** Too much traffic on one partition key. Each partition is limited to 3,000 read units and 1,000 write units per second. The fixes are a better key, write sharding (adding a suffix to the key), or a cache for reads.

A **GSI** (global secondary index) is asynchronous, and eventually consistent only.

DynamoDB is not the Dynamo paper: it uses leader-based replication per partition.

## MongoDB

**Embed** data that is contained, read together and low-cardinality. **Reference** data that is unbounded, or shared.

## Caching

A **cache** is a faster copy of data that is expensive to compute or fetch. Hit rate decides whether it is worth it.

| Pattern | Who talks to the database |
|---|---|
| **Cache-aside** | The application |
| **Read-through** | The cache |
| **Write-through** | The cache, on each write |
| **Write-behind** | The cache, later |

**Walk me through cache-aside. What can go wrong?**

```text
Read:  look in the cache. On a miss, read the database, and fill the cache.
Write: update the database, then delete the key.
```

What can go wrong: stale data, a stampede on expiry, and a cold cache after a restart.

**How do you keep a cache and the database consistent? Update or delete the key, and in what order?** Update the database first, then **delete** the key. If you delete first, another reader can re-fill the cache with the old value before your update commits. A short TTL covers what slips through.

**Eviction vs expiry.** LRU and LFU choose what to remove when memory is full. TTL is expiry.

### Three failure patterns

| Pattern | What happens | Fix |
|---|---|---|
| **Stampede** | A popular key expires, and everyone hits the database | A lock per key, or early refresh |
| **Penetration** | Requests for keys that do not exist | Cache the miss, or a Bloom filter |
| **Avalanche** | Many keys expire at once | Add random jitter to TTLs |

**A popular key expires, and the database falls over. What happened?** A stampede. Allow one request to rebuild the key, while the others wait, or serve the stale value.

**When not to cache:** a low hit rate, or volatile or sensitive data. Plan for cache failure.

**Why shouldn't a Redis lock alone protect a payment? What is a fencing token?** A lease protects nothing once a process pauses past its expiry, because two holders then exist. A **fencing token** is an increasing number that the storage layer checks, so that it rejects the older holder's writes.

## Analytics engines

**Why do columnar stores win at analytics and lose at point lookups?** A scan reads only the needed columns, and similar values compress well. A point lookup must reassemble a row from many columns.

| | Warehouse | Data lake | Lakehouse |
|---|---|---|---|
| Data | Cleaned, structured | Raw files | Files with warehouse features |
| Schema | On write | On read | Either |
| Cost | Higher | Cheap | Cheap |

**Medallion architecture:** bronze (raw), silver (cleaned), gold (business-level).

**Finance reports are slowing down production. What are your options?** A read replica (simple, but long queries delay replay), a warehouse fed by CDC, a materialized view, or scheduling them off-peak.

**HTAP** serves transactions and analytics from one database, through a columnar replica or in-memory store. **Why do some say it failed?** Resource contention, coupled scaling, and the rival pattern of separate engines over shared storage.

## Cloud and serverless

**Aurora storage:** "the log is the database". Compute sends redo to storage, with six copies across three Availability Zones.

**What does serverless Postgres actually separate, and what does scale to zero cost you?** It separates compute from storage. Scale to zero costs a cold start, so client timeouts must be raised, and capacity restarts small.

## Vector search

An **embedding** is a model's numeric form of content, so that similar meaning gives nearby vectors.

**When should you use exact search instead of ANN?** When the data is small, or filtered down to few rows, because exact search gives perfect recall. **ANN** (approximate nearest neighbor) trades recall for speed.

| Index | How | Tunable on a live index |
|---|---|---|
| **HNSW** | A layered proximity graph | `efSearch` only. `M` and `efConstruction` are fixed at build |
| **IVF** | k-means cells | `nprobe` |

**Product quantization** compresses vectors, trading recall for memory. Win recall back by reranking with exact distances.

**800 million vectors, a 200 GB RAM budget. Which index?** IVF with product quantization, because HNSW would not fit in memory. Rerank the top candidates with exact distances from disk.

**A query with a strict metadata filter returns two results, when the user wanted ten. Why?** Post-filtering: the index found 10 nearest, and the filter removed 8. Use iterative scans, a partial index, or filter first.

**pgvector or a dedicated vector database?** pgvector gives the same transactions, joins, backups and row-level security. Switch when scale or memory demands it.

**Hybrid retrieval** combines BM25 keyword search with vectors, then reranks.

Tenant and permission filters are correctness rules. Never relax them to fill the top k.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Choose NoSQL for "scale" with no numbers | You lose joins for nothing | Justify from access patterns |
| Model Cassandra like SQL | Slow, or impossible queries | One table per query |
| Use an unbounded partition | Reads and repairs break | Add a time bucket |
| Delete the cache key before the update | Stale data returns | Update, then delete |
| Give all keys the same TTL | An avalanche | Add jitter |
| Trust a Redis lock for money | Two holders are possible | Use fencing, or the database |
| Post-filter a vector search | Too few results | Filter during the search |

## Interview questions

**Q1. SQL or NoSQL for this workload? Justify it from the access patterns.**

I start with relational, unless the access patterns are simple key lookups at a huge scale, or the data shape really varies. I ask about query shapes, consistency, volume and team skills, and I say what I would give up.

**Q2. Model chat messages in Cassandra.**

Partition by room and a time bucket, and cluster by message time descending. The bucket keeps partitions bounded.

**Q3. Walk me through cache-aside. What can go wrong?**

On a read miss, the application loads from the database, and fills the cache. On a write, it updates the database, and deletes the key. Risks are stale data, a stampede, and a cold start.

**Q4. A popular key expires and the database falls over. What happened, and how do you prevent it?**

A cache stampede. I use a per-key lock so that only one request rebuilds it, serve the stale value meanwhile, and add jitter to TTLs.

**Q5. What is the difference between a data warehouse, a data lake and a lakehouse?**

A warehouse holds cleaned, structured data, with schema on write. A lake holds raw files, cheaply, with schema on read. A lakehouse adds warehouse features, such as transactions, on top of lake files.

**Q6. What is HTAP, and why do some people say it failed?**

One system for transactions and analytics. Critics point to resource contention and coupled scaling, and prefer separate engines fed by CDC.

**Q7. What is the difference between efSearch and efConstruction, and which can you tune on a live index?**

`efConstruction` sets build quality, and is fixed. `efSearch` sets the search effort, and can change per query, trading speed for recall.

## Practice

**1. You store user sessions with a 30-minute lifetime, read on every request. Which store?**

<details>
<summary>Show solution</summary>

A key-value store such as Redis, with a TTL. Loss is tolerable, since a user can log in again.

</details>

**2. An app needs account balances, with transfers. Which store?**

<details>
<summary>Show solution</summary>

A relational database. Transfers need atomic transactions and strong consistency.

</details>

**3. Why add jitter to cache TTLs?**

<details>
<summary>Show solution</summary>

So that many keys do not expire at once, and send a wave of requests to the database.

</details>

## Recap

- Start relational, and justify anything else from access patterns.
- Cassandra: one table per query, with bounded partitions.
- Cache-aside: update the database, then delete the key.
- Stampede, penetration and avalanche are the three failure patterns.
- Columnar stores win at scans, and lose at point lookups.
- Filter during a vector search, not after it.

**Next:** [Chapter 40: Database security](40-database-security.md)
