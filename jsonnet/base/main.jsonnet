local backup = import 'backup.libsonnet';

{
  // Override default configuration if needed
  local config = backup {
    config+: {
      backups: [
        {
          name: 'production',
          namespace: 'prod',
          dbAppConfig: 'cluster-prod-app',
          resticSecretName: 'prod-restic-secret',
          schedule: '0 */6 * * *',  // Every 6 hours
        },
        {
          name: 'staging',
          namespace: 'staging',
          dbAppConfig: 'cluster-staging-app',
          resticSecretName: 'staging-restic-secret',
          schedule: '0 0 * * *',  // Daily at midnight
        },
      ],
    },
  },

  // Generate all CronJobs
  cronJobs: config.cronJobs,
}