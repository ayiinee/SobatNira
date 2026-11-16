export const ACTIVE_ACCESS_SQL = `
  SELECT fm.user_id AS "userId", t.id AS "tenantId", t.name AS "tenantName",
         f.id AS "factoryId", f.name AS "factoryName", fm.role
  FROM sobatnira.factory_memberships fm
  JOIN sobatnira.tenant_memberships tm ON tm.tenant_id = fm.tenant_id AND tm.user_id = fm.user_id
  JOIN sobatnira.factories f ON f.tenant_id = fm.tenant_id AND f.id = fm.factory_id
  JOIN sobatnira.tenants t ON t.id = fm.tenant_id
  WHERE fm.user_id = $1::uuid AND fm.is_active AND tm.is_active AND f.is_active AND t.is_active
`;

// Parameters 1..3 are always the verified user, tenant and factory, respectively.
export const FACTORY_SCOPE_CTE = `authorized_scope AS (
  ${ACTIVE_ACCESS_SQL}
  AND fm.tenant_id = $2::uuid AND fm.factory_id = $3::uuid AND fm.role IN ('admin', 'owner')
)`;
