# 4. ER Modeling: Designing a Database Before You Build It

**Level:** Intermediate | **Interview priority:** Must know | **Before this:** [Chapter 2](02-relational-model-and-keys.md)

> **In one line:** An ER diagram shows the things a business tracks and how they relate, and it maps directly to tables.

## What you will learn

- Entities, attributes and relationships
- Cardinality and participation
- Weak entities, generalization and aggregation
- How to turn an ER diagram into tables
- How to go from English requirements to a diagram

## Where ER fits

```text
Requirements -> ER diagram -> Tables -> Indexes and storage
                (conceptual)  (logical)  (physical)
```

Normalization ([Chapter 23](../part-4-database-design/23-normalization.md)) then checks the tables.

## Entities and attributes

An **entity** is something the business tracks on its own. **Customer** is the entity type, and Alice Morgan is one entity.

| Attribute kind | Example |
|---|---|
| Simple or composite | Name, split into first and last |
| Single-valued or multivalued | Several phone numbers |
| Stored or derived | Birth date is stored, and age is derived |
| Key | `customer_id` |

## Relationships

A **relationship** links entities, and you find them from the verbs: Customer **places** Order.

**Degree** is how many entity types take part: binary (two), ternary (three), or unary, also called recursive (an employee manages employees).

### Cardinality and participation

**What is the difference between cardinality and participation?**

- **Cardinality** is the **maximum**: 1:1, 1:N or M:N.
- **Participation** is the **minimum**: total (every entity must take part) or partial (some may not).

Read every relationship in both directions:

```text
One customer places many orders.     Customer side: partial (Hana has none)
Each order is placed by one customer. Order side: total (every order has one)
```

The **(min, max)** form holds both: Order takes part as (1,1), Customer as (0,N). Books differ on which end of the line the numbers go, so check the notation.

### Notation

```text
Crow's foot (most common in industry)

CUSTOMER ||---------o{ ORDER
   exactly one        zero or many

Chen (textbooks)

[Customer] ---1--- <places> ===N=== [Order]
 rectangles are entities, diamonds are relationships,
 double lines mean total participation
```

### Relationship attributes

Some facts belong to the link, not to either entity. `quantity` and `unit_price` belong to the Order-Product link. On M:N relationships, they go in the junction table.

**The key of a relationship set:** both entity keys together for M:N, the many-side key for 1:N, and either key for 1:1.

## Weak entities

**What is a weak entity? How is its primary key formed?** It has no full key of its own, and exists only through an owner. Its key is the **owner's key plus a discriminator** (a partial key). For example, a dependent of an employee is identified by `(emp_id, dependent_name)`.

**Existence dependency is not the same as weak.** A payment needs an order, but `payments` has its own key, so it is a strong entity with total participation.

## Ternary relationships

**When would you keep a ternary relationship instead of splitting it?** When one fact needs all three entities at once. "Supplier S supplies part P to project J" is not the same as three separate facts, because three binary relationships can lose information.

**Modeling choices:**

- Attribute or entity? A phone stays a column until it has facts of its own, or there can be several.
- Relationship or entity? An action with its own history, such as an enrollment, may become an entity.

## Specialization, generalization and aggregation

**What is the difference?**

- **Specialization** is top-down: split Employee into Manager and Engineer.
- **Generalization** is bottom-up: merge Car and Truck into Vehicle.
- Both use **ISA** and attribute inheritance.
- **Aggregation** treats a relationship as an abstract entity, so that another relationship can attach to it. For example, an evaluation applies to the "instructor teaches course" relationship.

**Constraints:** disjoint vs overlapping, and total vs partial.

## From ER to tables

| ER element | Table design |
|---|---|
| Strong entity | One table. Flatten composite attributes, and drop derived ones |
| Weak entity | A table whose key is the owner's key plus the discriminator, with `ON DELETE CASCADE` |
| 1:N | A foreign key on the many side. No new table |
| Recursive 1:N | A foreign key into the same table (`manager_id`) |
| M:N | A junction table with both foreign keys |
| 1:1 | A foreign key with `UNIQUE` on the total-participation side, or one merged table |
| Multivalued attribute | A new table keyed by owner plus value |
| n-ary relationship | A table with all n foreign keys |

### Many-to-many

**How do you implement a many-to-many relationship?** With a junction table. `order_items` links orders and products.

```sql
SELECT o.order_id, p.product_name
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
JOIN products p ON p.product_id = i.product_id
WHERE o.order_id = 1001
ORDER BY p.product_name;
```

```text output
 order_id | product_name
----------+--------------
     1001 | Phone Case
     1001 | Phone X
(2 rows)
```

### The merge rule

**A and B are connected by R, which has no attributes. When can R's table be merged?** When R is 1:N, it folds into the many side as a foreign key. If the many side has total participation, the foreign key is `NOT NULL`. An M:N relationship can never merge.

### Minimum number of tables

One table per entity, one more per M:N relationship, one more per multivalued attribute, and normally none for a 1:N.

**Two entities linked by one 1:N and one M:N:** three tables.

### Mapping inheritance

| Option | Tables |
|---|---|
| Superclass table plus subclass tables | Parent, plus one per subclass |
| Subclass tables only | One per subclass (needs total specialization) |
| One table with a type column | Single table, with NULLs |
| One table with flags | Single table, for overlapping subclasses |

[Chapter 25](../part-4-database-design/25-schema-design-patterns.md) compares these.

## The sample database as an ER model

| Table | ER element |
|---|---|
| `departments`, `customers`, `products` | Strong entities |
| `employees` | Strong entity, with a recursive 1:N (`manager_id`) |
| `categories` | Strong entity, with a recursive 1:N (`parent_id`) |
| `orders` | Strong entity, 1:N from `customers` |
| `order_items` | M:N between `orders` and `products`, with attributes |
| `payments` | Strong entity, 1:N from `orders`, with total participation |

## From English to a diagram

1. List the **nouns**: these are entities.
2. List the **verbs**: these are relationships.
3. Find the quantity words: each, at most, many, must.
4. Write sentences in both directions.
5. Draw it, and find the keys.

**Worked example:** "Instructors teach courses, students register for courses, courses are allocated classrooms, and instructors guide students."

```text
Entities: Instructor, Course, Student, Classroom

Instructor teaches Course          M:N (or 1:N if one instructor per course)
Student registers for Course       M:N, with grade on the link
Course allocated to Classroom      N:1
Instructor guides Student          1:N
```

Tables: `instructors`, `courses`, `students`, `classrooms`, `teaches`, `registrations`, with `classroom_id` on `courses` and `advisor_id` on `students`.

**Relating SQL to an ERD:** `FROM` names entities, the `SELECT` list names attributes, and `JOIN` follows relationships.

A careful ER design should already be normalized. A dependency from a non-key attribute, such as `dept_name -> building` on an instructor table, signals a missing entity.

## Common mistakes

| What people do | What goes wrong | Do this instead |
|---|---|---|
| Mix up cardinality and participation | Wrong keys and `NOT NULL`s | Cardinality is max, participation is min |
| Put a list in a column | It breaks 1NF | Use a new table |
| Put M:N keys in a parent table | It cannot hold many values | Use a junction table |
| Put link facts on an entity | The facts are in the wrong place | Put them on the relationship |
| Call every dependent table weak | `payments` has its own key | Check for a full key |
| Store derived attributes | They go stale | Compute them |

## Interview questions

**Q1. What is the difference between cardinality and participation in an ER diagram?**

Cardinality is the maximum: 1:1, 1:N or M:N. Participation is the minimum: total means every entity must take part, and partial means some may not.

**Q2. What is a weak entity? How is its primary key formed?**

An entity with no full key of its own, which exists only through an owner. Its key is the owner's key plus a discriminator.

**Q3. How do you implement a many-to-many relationship in a relational database?**

With a junction table holding both foreign keys, usually with the pair as the primary key, plus any attributes of the link.

**Q4. Hotel rooms and persons have a many-to-many lodging relationship. Where do you store the rent payment?**

On the junction table, because it describes one person's stay in one room, not either alone.

**Q5. When can a relationship table be merged into an entity table?**

When the relationship is 1:N, it merges into the many side as a foreign key. With total participation, that foreign key is `NOT NULL`. An M:N cannot merge.

**Q6. What is the minimum number of tables for two entities linked by one 1:N and one M:N?**

Three: two entities and one junction table. The 1:N becomes a foreign key.

**Q7. When would you keep a ternary relationship instead of splitting it into binary relationships?**

When the fact needs all three at once. Splitting it can lose which supplier supplied which part to which project.

**Q8. What is the difference between generalization, specialization and aggregation?**

Specialization splits a type into subtypes, top-down. Generalization merges types into a supertype, bottom-up. Aggregation treats a relationship as an entity, so that another relationship can attach to it.

## Practice

**1. Draw the relationships for a library: members borrow copies of books.**

<details>
<summary>Show solution</summary>

```text
Book 1 --- N Copy          (a copy is of one book)
Member 1 --- N Loan N --- 1 Copy
```

A loan is an entity with its own dates, so it becomes a table with two foreign keys.

</details>

**2. Map this to tables: an employee has many skills, and a skill belongs to many employees, with a proficiency level.**

<details>
<summary>Show solution</summary>

```text
employees       (emp_id PK, ...)
skills          (skill_id PK, name)
employee_skills (emp_id FK, skill_id FK, proficiency, PK (emp_id, skill_id))
```

</details>

**3. An employee has many phone numbers. Is that a new entity?**

<details>
<summary>Show solution</summary>

It is a multivalued attribute, so it needs its own table: `employee_phones(emp_id, phone, PK (emp_id, phone))`.

</details>

## Recap

- Nouns are entities, and verbs are relationships.
- Cardinality is the max, and participation is the min.
- A weak entity's key is the owner's key plus a discriminator.
- 1:N is a foreign key on the many side.
- M:N is a junction table.
- A multivalued attribute is a new table.
- Facts about a link go on the link.

**Next:** [Chapter 5: Data types and NULL](05-data-types-and-null.md)
