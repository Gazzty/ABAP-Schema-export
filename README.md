================================================================================
PROGRAM:     Y_SCHEMA_EXPORT
TITLE:       PE01 Schema Export Tool
AUTHOR:      Gustavo T. Muiños
DESCRIPTION: Exports PE01 payroll schemas and related PCRs to a single text file
================================================================================

FEATURES
--------
- Recursive export: Discovers all schemas and rules referenced by main schema
- Dependency detection:
  * ACTIO function -> Exports related PCRs from T52C5
  * COPY function  -> Exports related schemas from T52C1
  * NEXTR operation -> Exports rules referenced within other rules
- Single file output: All content exported to one file (one authentication)
- Dynamic SQL: System independent across different SAP versions

TABLES USED
-----------
T52C0  - Schema directory
T52C1  - Schema lines
T52C5  - Personnel calculation rules
T52CE  - Schema descriptions (texts)

INSTALLATION
------------
1. Create a new report in SE38 or ADT
2. Copy the source code
3. Create text element: TEXT-001 = "Export Parameters"
4. Activate the program

USAGE
-----
1. Execute the report (SE38 or F8)
2. Enter Schema name (4 characters, e.g. X000)
3. Select Output folder using F4 help
4. Execute (F8)

SELECTION SCREEN PARAMETERS
---------------------------
P_SCHMA  - Schema name (4 chars)    - Required
P_PATH   - Output folder path       - Required

OUTPUT FILE
-----------
Creates: {SCHEMA}_EXPORT.txt

File structure:
  - Header with export date and total objects
  - Each schema/rule separated by visual markers
  - Footer with count of schemas and rules

LOGIC FLOW
----------
1. User enters schema -> Added to processing queue
2. For each schema:
   - Read T52C1 lines
   - FUNCO = ACTIO -> Add rule to queue
   - FUNCO = COPY  -> Add schema to queue
3. For each rule:
   - Read T52C5 lines
   - VESSION = NEXTR -> Add referenced rule to queue
4. Export all processed objects to single file

ERROR HANDLING
--------------
- Missing schemas/rules are skipped
- Table structure differences handled dynamically
- File write errors displayed as warnings

================================================================================
