#!/usr/bin/env bash
set -euo pipefail

base=""
broker_ip=""
broker_container=""
admin_user="ci-admin"
admin_pass="CiTest!2026x"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      base="${2%/}"
      shift 2
      ;;
    --broker-ip)
      broker_ip="$2"
      shift 2
      ;;
    --broker-container)
      broker_container="$2"
      shift 2
      ;;
    --admin-user)
      admin_user="$2"
      shift 2
      ;;
    --admin-pass)
      admin_pass="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[ -n "$base" ] || { echo "--base-url is required" >&2; exit 1; }
[ -n "$broker_ip" ] || { echo "--broker-ip is required" >&2; exit 1; }
[ -n "$broker_container" ] || { echo "--broker-container is required" >&2; exit 1; }

echo "Waiting for health: ${base}/health ..."
for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 "${base}/health" >/dev/null 2>&1; then
    echo "Health check passed"
    break
  fi
  sleep 2
done

echo "Setting up admin ($admin_user)..."
curl -fsS -X POST "${base}/api/v1/auth/setup" \
  -H "Content-Type: application/json" \
  -d "{\"auth_enabled\":true,\"admin_username\":\"${admin_user}\",\"admin_password\":\"${admin_pass}\"}" >/dev/null

token=$(curl -fsS -X POST "${base}/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${admin_user}\",\"password\":\"${admin_pass}\"}" \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

[ -n "$token" ] || { echo "Failed to obtain access token from login" >&2; exit 1; }
echo "Admin seeded, token obtained"

echo "Adding printer against broker $broker_ip..."
printer_res=$(curl -fsS -X POST "${base}/api/v1/printers/" \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Contract X1C\",\"serial_number\":\"00M09A000000001\",\"ip_address\":\"${broker_ip}\",\"access_code\":\"12345678\",\"model\":\"X1C\"}")

printer_id=$(echo "$printer_res" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
[ -n "$printer_id" ] || { echo "Failed to get printer_id from $printer_res" >&2; exit 1; }
echo "Printer $printer_id added"

echo "Publishing retained printer report..."
docker exec "$broker_container" mosquitto_pub \
  -h localhost -p 8883 --insecure \
  --cafile /mosquitto/certs/server.crt \
  -t "device/00M09A000000001/report" -r \
  -m '{"print":{"gcode_state":"RUNNING","mc_percent":42,"mc_remaining_time":75,"nozzle_temper":215.0,"bed_temper":60.0,"subtask_name":"contract-probe.3mf","layer_num":30,"total_layer_num":120,"ams":{"ams":[{"id":0,"tray":[{"id":0,"tray_type":"PLA","tray_color":"FF0000FF","tray_info_idx":"GFL99","tray_sub_brands":"PLA Basic"},{"id":1,"tray_type":"PLA","tray_color":"00FF00FF","tray_info_idx":"GFL99","tray_sub_brands":"PLA Basic"}]}],"ams_exist_bits":"1"}}}'
echo "Report published"

echo "Waiting for printer status to report RUNNING with AMS..."
for _ in $(seq 1 30); do
  status=$(curl -fsS -H "Authorization: Bearer $token" "${base}/api/v1/printers/${printer_id}/status" 2>/dev/null || true)
  if echo "$status" | grep -q '"RUNNING"' && echo "$status" | grep -q '"ams_exists":true'; then
    echo "Printer status RUNNING with AMS confirmed"
    break
  fi
  sleep 1
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
probe_3mf="${script_dir}/contract-probe.3mf"
[ -f "$probe_3mf" ] || { echo "Missing $probe_3mf" >&2; exit 1; }

echo "Uploading 3MF file..."
file_res=$(curl -fsS -X POST "${base}/api/v1/library/files" \
  -H "Authorization: Bearer $token" \
  -F "file=@${probe_3mf}")

file_id=$(echo "$file_res" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
[ -n "$file_id" ] || { echo "Failed to get file_id from $file_res" >&2; exit 1; }
echo "Library file $file_id uploaded"

echo "Creating queue item..."
queue_res=$(curl -fsS -X POST "${base}/api/v1/queue/" \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  -d "{\"printer_id\":${printer_id},\"library_file_id\":${file_id}}")

echo "Queue item created: $queue_res"
echo "Seeding completed successfully"
