// Nested savepoints keep application transactions inside a rollback-only fixture.
function useTransactionFixture(database, client) {
  let sequence = 0;
  database.query = (sql, values) => client.query(sql, values);
  database.transaction = async (work) => {
    const savepoint = `fixture_operation_${++sequence}`;
    await client.query(`SAVEPOINT ${savepoint}`);
    try {
      const result = await work({ query: (sql, values) => {
        // The outer rollback fixture already owns a transaction with writes.
        // Its private uncommitted data is stable; nested reads cannot change isolation.
        if (sql === 'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY') return Promise.resolve({ rows: [], rowCount: 0 });
        return client.query(sql, values);
      } });
      await client.query('SET CONSTRAINTS ALL IMMEDIATE');
      await client.query('SET CONSTRAINTS ALL DEFERRED');
      await client.query(`RELEASE SAVEPOINT ${savepoint}`);
      return result;
    } catch (error) {
      await client.query(`ROLLBACK TO SAVEPOINT ${savepoint}`);
      await client.query(`RELEASE SAVEPOINT ${savepoint}`);
      throw error;
    }
  };
}
module.exports = { useTransactionFixture };
