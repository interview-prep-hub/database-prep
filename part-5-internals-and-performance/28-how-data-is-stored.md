# 28. How Data Is Stored: Pages, Files and the Buffer Pool

**Level:** Intermediate | **Interview priority:** Should know | **Before this:** Part 2

> **In one line:** A database reads and writes fixed-size pages, keeps popular ones in memory, and the main cost of most queries is how many pages they touch.

## What you will learn

- The storage hierarchy, and why random reads cost more
- Pages, slotted pages and row addresses
- RAID levels
- Row stores vs column stores
- The buffer pool, and why LRU can fail

**Why start here?** The main cost of most queries is how many pages they read, so every later chapter in this part comes back to that.

## The storage hierarchy

| Storage | Rough access time | Keeps data without power |
|---|---|---|
| RAM | 100 nanoseconds | No |
| SSD | 100 microseconds | Yes |
| Hard disk | 10 milliseconds | Yes |

Disk is about 100,000 times slower than RAM. That gap is why databases work so hard to avoid I/O.

**Hard disks.** Access time is seek, plus rotational latency, plus transfer. So sequential reads beat random reads by a wide margin.

**SSDs** have no seek or rotation, but flash must be erased before it is rewritten, erasing works on large blocks, and cells wear out.

**Why is sequential I/O faster than random I/O, and does that still hold on SSDs?** On a hard disk, each random read needs a seek. On an SSD the gap is much smaller, but sequential access still wins, because of prefetching and batching.

## Pages

The **page** (or **block**) is the smallest unit a database reads or writes.

| Engine | Default page size |
|---|---|
| PostgreSQL | 8 KB |
| SQL Server | 8 KB |
| InnoDB | 16 KB |
| Oracle | Usually 8 KB, set at creation |

To change one row, the database reads a whole page.

### Slotted pages

```text
+----------------------------------------------+
| Header | Slot 1 | Slot 2 | Slot 3 | -->      |
|                                              |
|                free space                    |
|                                              |
|          <-- | Record 3 | Record 2 | Record 1|
+----------------------------------------------+
```

The header and slot array grow from the front, and records grow from the back, with free space in the middle.

**Why does moving a record inside a page not break references to it?** References point to the slot number, not the byte position. The record can move, and only the slot's offset changes.

**Record layout.** Fixed-length records fit equal slots. Variable-length records keep a header of (offset, length) pairs, and a null bitmap.

### Row addresses

A **record ID** is (page number, slot number).

**PostgreSQL:**

```sql postgres
SELECT ctid, first_name FROM employees WHERE emp_id <= 2 ORDER BY emp_id;
```

```text output
 ctid  | first_name
-------+------------
 (0,1) | Sara
 (0,2) | James
(2 rows)
```

**Oracle:**

```sql oracle
SELECT ROWID, first_name FROM employees WHERE emp_id <= 2;
```

An address is not a stable key. It can change after an `UPDATE`, or a `VACUUM FULL`.

### Block arithmetic

**Blocking factor** = floor(block size / record size). **Unspanned** records never cross a block boundary, and waste the remainder.

```text
Block 4096 bytes, record 100 bytes
Blocking factor: floor(4096 / 100) = 40 records per block
1,000,000 records need ceil(1000000 / 40) = 25,000 blocks
```

## How storage is organized

**Oracle:** tablespace (one or more data files) > segment > extent > data block.

**PostgreSQL:** a table is a set of files, split at 1 GB.

**What are a tablespace, a segment, an extent and a data block in Oracle?** A tablespace is a logical store made of data files. A segment is one object's space, such as a table. An extent is a run of contiguous blocks. A block is the smallest unit of I/O.

**Row chaining vs migration** are covered in [Chapter 35](../part-6-architecture-and-scale/35-database-architecture.md).

**Large values.** PostgreSQL **TOAST** compresses values, or moves them out of line, when a row is wider than about 2 KB. Oracle stores LOBs in their own segments.

**You deleted 2 million rows from a 10 million row table, and the table size did not change. Why?** Deleted space is marked free for reuse inside the file, not returned to the operating system. On PostgreSQL, `VACUUM FULL` shrinks it. On Oracle, `ALTER TABLE ... SHRINK SPACE` or `MOVE` does. On Oracle, the **high water mark** also stays, so full scans still read those empty blocks.

## File organizations

| Organization | Insert | Lookup by key | Range scan |
|---|---|---|---|
| Heap | Fast | Needs an index | Needs an index |
| Sorted | Slow | Binary search | Fast |
| Hash | Fast | Fast | Poor |
| B+ tree | Medium | Fast | Fast |

## RAID

**What is the main goal of RAID?** Reliability through redundancy, and speed through striping.

| Level | How | Usable capacity | Failures survived | Good for |
|---|---|---|---|---|
| RAID 0 | Striping | All | 0 | Speed, no safety |
| RAID 1 | Mirroring | Half | 1 per pair | Logs |
| RAID 5 | Striping with parity | n - 1 disks | 1 | Read-heavy data |
| RAID 10 | Mirrors, striped | Half | 1 per mirror | Write-heavy databases |

**Pick RAID 10 for write-heavy databases.** RAID 5 pays a write penalty, because each write must update parity.

**Array mean time to failure** falls as disks are added: roughly one disk's MTTF divided by the number of disks. That is why striping alone is risky.

## Row store vs column store

```text
Row store:     [1, Sara, 180000] [2, James, 95000] [3, Priya, 120000]

Column store:  [1, 2, 3]  [Sara, James, Priya]  [180000, 95000, 120000]
```

| | Row store | Column store |
|---|---|---|
| Best for | OLTP: one row at a time | OLAP: a few columns over many rows |
| Writes | Fast | Slower |
| Compression | Modest | Excellent |

**When would you choose a column store?** For analytics that scan a few columns of many rows, because only those columns are read, and similar values compress well. Examples are Redshift, Snowflake and ClickHouse.

## The buffer pool

The **buffer pool** is a memory area of page-sized **frames** that caches disk pages. It is the **buffer cache** on Oracle, `shared_buffers` on PostgreSQL, and the buffer pool on InnoDB.

**Frame metadata:**

- **Pin count:** how many are using the page. Only frames with pin count 0 can be evicted.
- **Dirty bit:** the page changed, and must be written before eviction.

### Replacement policies

**LRU** evicts the least recently used page. **Clock** is a cheap approximation: a hand sweeps the frames, and a reference bit gives a page a second chance.

### Sequential flooding

**Why does LRU handle a repeated large scan badly?** When a repeated scan is one page larger than the pool, LRU gets zero hits.

```text
Pool of 3 frames, pages A B C D, read twice

Read A: [A]
Read B: [A B]
Read C: [A B C]
Read D: evict A, [B C D]
Read A: evict B, [C D A]      miss
Read B: evict C, [D A B]      miss
Read C: evict D, [A B C]      miss
Read D: evict A, [B C D]      miss
```

MRU (evict the most recently used) does better here. Engines defend against it too: InnoDB uses midpoint insertion, so that a big scan cannot push out hot pages.

**Why doesn't a DBMS simply rely on the operating system's page cache?** Eviction and prefetch should follow query plans, which the OS cannot see. And write-ahead logging needs precise control over when pages reach disk.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Expect a table to shrink after `DELETE` | The file stays the same size | Reclaim the space explicitly |
| Use `ctid` or `ROWID` as a stable key | It can change | Use a primary key |
| Use RAID 5 for heavy writes | The parity penalty | Use RAID 10 |
| Treat RAID as a backup | It does not stop bad deletes | Take backups |
| Use a row store for huge analytics | Slow scans | Use a column store |

## Interview questions

**Q1. What is the main goal of RAID, and how do RAID 0, 1 and 5 differ?**

Reliability and speed. RAID 0 stripes with no redundancy. RAID 1 mirrors. RAID 5 stripes with parity, so it survives one disk failure, with a write penalty.

**Q2. Explain the slotted page layout. Why does moving a record inside a page not break references to it?**

A slot array at the front of the page points to records stored from the back. External references use the slot number, so a record can move inside the page, and only its slot changes.

**Q3. You deleted 2 million rows from a 10 million row table and the table size did not change. Why?**

Deleted space is kept for reuse inside the file, and not returned to the OS. Reclaiming it needs `VACUUM FULL` or a table rebuild.

**Q4. When would you choose a column store over a row store?**

For analytics that read a few columns across many rows. For OLTP with many small writes, a row store is the better choice.

**Q5. What is the role of the buffer pool? What do the pin count and dirty bit mean?**

It caches disk pages in memory, to avoid slow I/O. The pin count says how many are using a page, so it cannot be evicted. The dirty bit says it changed, and must be written first.

**Q6. Why doesn't a DBMS simply rely on the operating system's page cache?**

The DBMS knows the query plan, so it can prefetch and evict better. And it must control when pages are written, to keep write-ahead logging correct.

## Practice

**1. Records are 256 bytes, and blocks are 4096 bytes. How many blocks do 10,000 records need, unspanned?**

<details>
<summary>Show solution</summary>

```text
Blocking factor: floor(4096 / 256) = 16
Blocks: ceil(10000 / 16) = 625
```

</details>

**2. Four disks, each with an MTTF of 100,000 hours, are in a RAID 0 array. Roughly what is the array's MTTF?**

<details>
<summary>Show solution</summary>

`100000 / 4 = 25,000` hours. Any one disk failing loses the array.

</details>

## Recap

- The page is the unit of I/O, and pages read is the main cost.
- A slotted page lets records move without breaking references.
- Deleted space stays in the file.
- RAID 10 suits write-heavy databases, and RAID is not a backup.
- Row stores suit OLTP, and column stores suit analytics.
- LRU fails on a scan just larger than the pool.

**Next:** [Chapter 29: Indexes](29-indexes.md)
