terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}
# Used to interact with the resources supported by Kubernetes.
# The provider needs to be configured with the proper credentials before it can be used.
provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_manifest" "clusterrole_prometheus" {
  manifest = {
    "apiVersion" = "rbac.authorization.k8s.io/v1"
    "kind" = "ClusterRole"
    "metadata" = {
      "name" = "prometheus"
    }
    "rules" = [
      {
        "apiGroups" = [
          "",
        ]
        "resources" = [
          "nodes",
          "nodes/proxy",
          "services",
          "endpoints",
          "pods",
        ]
        "verbs" = [
          "get",
          "list",
          "watch",
        ]
      },
      {
        "apiGroups" = [
          "extensions",
        ]
        "resources" = [
          "ingresses",
        ]
        "verbs" = [
          "get",
          "list",
          "watch",
        ]
      },
      {
        "nonResourceURLs" = [
          "/metrics",
        ]
        "verbs" = [
          "get",
        ]
      },
    ]
  }
}

resource "kubernetes_manifest" "clusterrolebinding_prometheus" {
  manifest = {
    "apiVersion" = "rbac.authorization.k8s.io/v1"
    "kind" = "ClusterRoleBinding"
    "metadata" = {
      "name" = "prometheus"
    }
    "roleRef" = {
      "apiGroup" = "rbac.authorization.k8s.io"
      "kind" = "ClusterRole"
      "name" = "prometheus"
    }
    "subjects" = [
      {
        "kind" = "ServiceAccount"
        "name" = "default"
        "namespace" = "monitoring"
      },
    ]
  }
}

resource "kubernetes_manifest" "configmap_monitoring_prometheus_server_conf" {
  manifest = {
    "apiVersion" = "v1"
    "data" = {
      "prometheus.rules" = <<-EOT
      groups:
      - name: devopscube demo alert
        rules:
        - alert: High Pod Memory
          expr: sum(container_memory_usage_bytes) > 1
          for: 1m
          labels:
            severity: slack
          annotations:
            summary: High Memory Usage
      EOT
      "prometheus.yml" = <<-EOT
      global:
        scrape_interval: 5s
        evaluation_interval: 5s
      rule_files:
        - /etc/prometheus/prometheus.rules
      alerting:
        alertmanagers:
        - scheme: http
          static_configs:
          - targets:
            - "alertmanager.monitoring.svc:9093"
      scrape_configs:
        - job_name: 'node-exporter'
          kubernetes_sd_configs:
            - role: endpoints
          relabel_configs:
          - source_labels: [__meta_kubernetes_endpoints_name]
            regex: 'node-exporter'
            action: keep
        - job_name: 'kubernetes-apiservers'
          kubernetes_sd_configs:
          - role: endpoints
          scheme: https
          tls_config:
            ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
          relabel_configs:
          - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
            action: keep
            regex: default;kubernetes;https
        - job_name: 'kubernetes-nodes'
          scheme: https
          tls_config:
            ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
          kubernetes_sd_configs:
          - role: node
          relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)
          - target_label: __address__
            replacement: kubernetes.default.svc:443
          - source_labels: [__meta_kubernetes_node_name]
            regex: (.+)
            target_label: __metrics_path__
            replacement: /api/v1/nodes/$${1}/proxy/metrics
        - job_name: 'kubernetes-pods'
          kubernetes_sd_configs:
          - role: pod
          relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__
          - action: labelmap
            regex: __meta_kubernetes_pod_label_(.+)
          - source_labels: [__meta_kubernetes_namespace]
            action: replace
            target_label: kubernetes_namespace
          - source_labels: [__meta_kubernetes_pod_name]
            action: replace
            target_label: kubernetes_pod_name
        - job_name: 'kube-state-metrics'
          static_configs:
            - targets: ['kube-state-metrics.kube-system.svc.cluster.local:8080']
        - job_name: 'kubernetes-cadvisor'
          scheme: https
          tls_config:
            ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
          kubernetes_sd_configs:
          - role: node
          relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)
          - target_label: __address__
            replacement: kubernetes.default.svc:443
          - source_labels: [__meta_kubernetes_node_name]
            regex: (.+)
            target_label: __metrics_path__
            replacement: /api/v1/nodes/$${1}/proxy/metrics/cadvisor
        - job_name: 'kubernetes-service-endpoints'
          kubernetes_sd_configs:
          - role: endpoints
          relabel_configs:
          - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
            action: replace
            target_label: __scheme__
            regex: (https?)
          - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
            action: replace
            target_label: __address__
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
          - action: labelmap
            regex: __meta_kubernetes_service_label_(.+)
          - source_labels: [__meta_kubernetes_namespace]
            action: replace
            target_label: kubernetes_namespace
          - source_labels: [__meta_kubernetes_service_name]
            action: replace
            target_label: kubernetes_name
      EOT
    }
    "kind" = "ConfigMap"
    "metadata" = {
      "labels" = {
        "name" = "prometheus-server-conf"
      }
      "name" = "prometheus-server-conf"
      "namespace" = "monitoring"
    }
  }
}

resource "kubernetes_manifest" "deployment_monitoring_prometheus_deployment" {
  manifest = {
    "apiVersion" = "apps/v1"
    "kind" = "Deployment"
    "metadata" = {
      "labels" = {
        "app" = "prometheus-server"
      }
      "name" = "prometheus-deployment"
      "namespace" = "monitoring"
    }
    "spec" = {
      "replicas" = 1
      "selector" = {
        "matchLabels" = {
          "app" = "prometheus-server"
        }
      }
      "template" = {
        "metadata" = {
          "labels" = {
            "app" = "prometheus-server"
          }
        }
        "spec" = {
          "containers" = [
            {
              "args" = [
                "--storage.tsdb.retention.time=12h",
                "--config.file=/etc/prometheus/prometheus.yml",
                "--storage.tsdb.path=/prometheus/",
              ]
              "image" = "prom/prometheus"
              "name" = "prometheus"
              "ports" = [
                {
                  "containerPort" = 9090
                },
              ]
              "resources" = {
                "limits" = {
                  "cpu" = 1
                  "memory" = "1Gi"
                }
                "requests" = {
                  "cpu" = "500m"
                  "memory" = "500M"
                }
              }
              "volumeMounts" = [
                {
                  "mountPath" = "/etc/prometheus/"
                  "name" = "prometheus-config-volume"
                },
                {
                  "mountPath" = "/prometheus/"
                  "name" = "prometheus-storage-volume"
                },
              ]
            },
          ]
          "volumes" = [
            {
              "configMap" = {
                "defaultMode" = 420
                "name" = "prometheus-server-conf"
              }
              "name" = "prometheus-config-volume"
            },
            {
              "emptyDir" = {}
              "name" = "prometheus-storage-volume"
            },
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "service_monitoring_prometheus_service" {
  manifest = {
    "apiVersion" = "v1"
    "kind" = "Service"
    "metadata" = {
      "annotations" = {
        "prometheus.io/port" = "9090"
        "prometheus.io/scrape" = "true"
      }
      "name" = "prometheus-service"
      "namespace" = "monitoring"
    }
    "spec" = {
      "ports" = [
        {
          "nodePort" = 30000
          "port" = 8080
          "targetPort" = 9090
        },
      ]
      "selector" = {
        "app" = "prometheus-server"
      }
      "type" = "NodePort"
    }
  }
}
