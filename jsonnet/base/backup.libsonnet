{
  local k = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet',
  local cronjob = k.batch.v1.cronJob,
  local container = k.core.v1.container,
  local envFrom = k.core.v1.envFrom,
  local envVar = k.core.v1.envVar,
  local envVarFrom = k.core.v1.envVarFrom,
  
  // Configuration parameters
  config:: {
    backups: [
      {
        name: 'example',
        namespace: 'default',
        dbAppConfig: 'cluster-example-app',
        resticSecretName: 'restic-secret',
        schedule: '0 0 * * *',
      },
    ],
    resticKeep: {
      hourly: 24,
      daily: 7,
      weekly: 4,
      monthly: 12,
      yearly: 7,
    },
  },

  // Helper function to create a single backup CronJob
  makeCronJob(backup)::
    cronjob.new('restic-backup-' + backup.name) +
    cronjob.metadata.withNamespace(backup.namespace) +
    cronjob.spec.withSchedule(backup.schedule) +
    cronjob.spec.jobTemplate.spec.template.spec.withContainers([
      container.new('restic-backup', 'ghcr.io/haosgames/restic-pg-dump-docker:latest') +
      container.withImagePullPolicy('IfNotPresent') +
      container.withCommand(['backup.sh']) +
      container.withEnvFrom([
        envFrom.secretRef.withName(backup.resticSecretName),
      ]) +
      container.withEnv([
        // Database configuration from secret
        envVarFrom.new() +
        envVarFrom.secretKeyRef.withName(backup.dbAppConfig) +
        envVarFrom.secretKeyRef.withKey('host') +
        envVar.withName('PGHOST'),
        
        envVarFrom.new() +
        envVarFrom.secretKeyRef.withName(backup.dbAppConfig) +
        envVarFrom.secretKeyRef.withKey('port') +
        envVar.withName('PGPORT'),
        
        envVarFrom.new() +
        envVarFrom.secretKeyRef.withName(backup.dbAppConfig) +
        envVarFrom.secretKeyRef.withKey('user') +
        envVar.withName('PGUSER'),
        
        envVarFrom.new() +
        envVarFrom.secretKeyRef.withName(backup.dbAppConfig) +
        envVarFrom.secretKeyRef.withKey('password') +
        envVar.withName('PGPASSWORD'),
        
        envVarFrom.new() +
        envVarFrom.secretKeyRef.withName(backup.dbAppConfig) +
        envVarFrom.secretKeyRef.withKey('dbname') +
        envVar.withName('PGDATABASE'),
        
        // Restic keep configuration
        envVar.new('RESTIC_KEEP_HOURLY', std.toString($.config.resticKeep.hourly)),
        envVar.new('RESTIC_KEEP_DAILY', std.toString($.config.resticKeep.daily)),
        envVar.new('RESTIC_KEEP_WEEKLY', std.toString($.config.resticKeep.weekly)),
        envVar.new('RESTIC_KEEP_MONTHLY', std.toString($.config.resticKeep.monthly)),
        envVar.new('RESTIC_KEEP_YEARLY', std.toString($.config.resticKeep.yearly)),
      ]),
    ]) +
    cronjob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure'),

  // Generate all CronJobs
  cronJobs: {
    ['restic-backup-' + backup.name]: $.makeCronJob(backup)
    for backup in $.config.backups
  },
}