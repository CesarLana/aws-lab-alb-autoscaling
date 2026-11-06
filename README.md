# AWS Lab: Alta Disponibilidade com ALB e Auto Scaling Multi-AZ

[![AWS](https://img.shields.io/badge/AWS-Cloud-orange?logo=amazon-aws)](https://aws.amazon.com/)
[![Service](https://img.shields.io/badge/Service-ALB%20%7C%20AutoScaling%20%7C%20EC2-232F3E?logo=amazon-aws)](https://aws.amazon.com/ec2/)
[![OS](https://img.shields.io/badge/OS-Amazon%20Linux%202023-blue)](https://aws.amazon.com/linux/amazon-linux-2023/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Implementação prática de arquitetura resiliente, elástica e de alta disponibilidade na Amazon Web Services (AWS). O projeto provisiona um **Application Load Balancer (ALB)** distribuindo tráfego HTTP entre instâncias EC2 hospedadas em múltiplas Zonas de Disponibilidade (**Multi-AZ**), gerenciadas por um **Auto Scaling Group (ASG)** com política de **Target Tracking** baseada em utilização de CPU.

---

## 🏛️ Diagrama de Arquitetura

```mermaid
flowchart TD
    subgraph Internet["🌐 Tráfego Externo"]
        Users["Usuários / Clientes HTTP"]
    end

    subgraph AWS_Cloud["☁️ AWS Region (us-east-1)"]
        subgraph VPC["VPC (10.0.0.0/16)"]
            IGW["Internet Gateway"]
            
            subgraph Public_Tier["Tier Público (Load Balancer)"]
                ALB["Application Load Balancer (ALB)<br/>Porta 80 (HTTP)"]
                SG_ALB["Security Group: sg-alb<br/>Inbound: 0.0.0.0/0:80"]
            end

            subgraph MultiAZ_Tier["Auto Scaling Group (Min: 2 | Desired: 2 | Max: 4)"]
                subgraph AZ_A["Availability Zone: us-east-1a"]
                    EC2_A["EC2 Web Server A<br/>Amazon Linux 2023<br/>Apache (httpd)"]
                end

                subgraph AZ_B["Availability Zone: us-east-1b"]
                    EC2_B["EC2 Web Server B<br/>Amazon Linux 2023<br/>Apache (httpd)"]
                end

                SG_EC2["Security Group: sg-ec2-web<br/>Inbound: sg-alb:80 ONLY"]
            end

            TG["Target Group (HTTP:80)<br/>Health Check: /healthz"]
        end

        subgraph Monitoring["📊 Observabilidade & Automação"]
            CW_Metrics["Amazon CloudWatch<br/>Métrica: ASGAverageCPUUtilization"]
            ASG_Policy["Target Tracking Policy<br/>Meta: 50% CPU"]
        end
    end

    Users -->|HTTP :80| IGW
    IGW --> ALB
    ALB -. Protegido por .- SG_ALB
    ALB -->|Roteamento Round-Robin| TG
    TG -->|Encaminha tráfego| EC2_A
    TG -->|Encaminha tráfego| EC2_B
    EC2_A -. Protegido por .- SG_EC2
    EC2_B -. Protegido por .- SG_EC2
    
    EC2_A & EC2_B -->|Envia métricas| CW_Metrics
    CW_Metrics -->|Trigger > 50%| ASG_Policy
    ASG_Policy -->|Scale-Out (+ Instâncias)| MultiAZ_Tier
```

---

## 📁 Estrutura do Repositório

```text
aws-lab-alb-autoscaling/
├── .gitignore                      # Ignora credenciais, logs e arquivos de ambiente
├── README.md                       # Documentação técnica completa e guia de execução
├── policies/
│   └── asg-policy.json             # Definição de Target Tracking Scaling Policy (50% CPU)
└── scripts/
    ├── user_data.sh                # Script de bootstrap EC2 (Apache, IMDSv2, página de status)
    └── stress_test.sh              # Gerador de carga sintética de CPU para acionamento do ASG
```

---

## ⚙️ Decisões Técnicas de Arquitetura

1. **Isolamento de Camadas (Security Group Chaining):**
   - As instâncias EC2 não recebem conexões diretas da internet pública na porta 80. O Security Group das instâncias aceita requisições HTTP estritamente originadas do Security Group do ALB (`sg-alb`).
2. **IMDSv2 Obrigatório:**
   - O script `scripts/user_data.sh` utiliza o **Instance Metadata Service Version 2 (IMDSv2)** com tokens de sessão temporários para prevenir ataques do tipo SSRF (Server-Side Request Forgery).
3. **Distribuição Multi-AZ:**
   - O Auto Scaling Group balanceia instâncias simetricamente entre `us-east-1a` e `us-east-1b`, garantindo disponibilidade mesmo em caso de indisponibilidade de um data center inteiro.
4. **Política Target Tracking (Métrica 50% CPU):**
   - Em vez de regras simples de degrau (Simple Scaling), o Target Tracking ajusta dinamicamente a capacidade do grupo para estabilizar o uso médio de CPU em 50%, com cooldown configurado para evitar flutuações agressivas (flapping).

---

## 🚀 Guia Passo a Passo de Implantação

### Pré-requisitos
- Conta AWS com permissões para EC2, VPC, ALB e CloudWatch.
- AWS CLI configurado localmente (`aws configure`).

---

### Passo 1: Obter Identificadores de Rede (VPC e Subnets)

```bash
# Obter ID da VPC padrão
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)

# Obter IDs de duas subnets em Zonas de Disponibilidade diferentes
SUBNET_A=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=us-east-1a" --query "Subnets[0].SubnetId" --output text)
SUBNET_B=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=us-east-1b" --query "Subnets[0].SubnetId" --output text)

echo "VPC: $VPC_ID | Subnet A: $SUBNET_A | Subnet B: $SUBNET_B"
```

---

### Passo 2: Criar Security Groups com Encadeamento de Permissões

```bash
# 1. Security Group para o Application Load Balancer
SG_ALB_ID=$(aws ec2 create-security-group \
  --group-name "sg-lab-alb" \
  --description "Acesso publico HTTP para o Application Load Balancer" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" --output text)

# Liberar porta 80 pública para o ALB
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ALB_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# 2. Security Group para as Instâncias EC2 (apenas tráfego vindo do ALB)
SG_EC2_ID=$(aws ec2 create-security-group \
  --group-name "sg-lab-ec2" \
  --description "Trafego restrito vindo do ALB" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" --output text)

# Liberar porta 80 referenciando o ID do SG do ALB
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_EC2_ID" \
  --protocol tcp \
  --port 80 \
  --source-group "$SG_ALB_ID"
```

---

### Passo 3: Criar o Target Group e o Application Load Balancer

```bash
# 1. Criar Target Group
TG_ARN=$(aws elbv2 create-target-group \
  --name "tg-lab-asg" \
  --protocol HTTP \
  --port 80 \
  --vpc-id "$VPC_ID" \
  --target-type instance \
  --health-check-protocol HTTP \
  --health-check-port 80 \
  --health-check-path "/healthz" \
  --health-check-interval-seconds 15 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --query "TargetGroups[0].TargetGroupArn" --output text)

# 2. Criar Application Load Balancer Multi-AZ
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "alb-lab-web" \
  --subnets "$SUBNET_A" "$SUBNET_B" \
  --security-groups "$SG_ALB_ID" \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)

# Obter o DNS Name do ALB
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query "LoadBalancers[0].DNSName" --output text)

# 3. Criar Listener HTTP na porta 80 apontando para o Target Group
aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN"
```

---

### Passo 4: Criar o Launch Template

```bash
# Obter o ID da AMI mais recente do Amazon Linux 2023
AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

# Codificar o script de user_data em Base64
USER_DATA_B64=$(base64 -w 0 scripts/user_data.sh 2>/dev/null || base64 scripts/user_data.sh)

# Criar o Launch Template
aws ec2 create-launch-template \
  --launch-template-name "lt-lab-web" \
  --version-description "v1-web-al2023" \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"t3.micro\",
    \"SecurityGroupIds\": [\"$SG_EC2_ID\"],
    \"UserData\": \"$USER_DATA_B64\",
    \"MetadataOptions\": {
      \"HttpTokens\": \"required\",
      \"HttpPutResponseHopLimit\": 2,
      \"HttpEndpoint\": \"enabled\"
    },
    \"TagSpecifications\": [
      {
        \"ResourceType\": \"instance\",
        \"Tags\": [{\"Key\": \"Name\", \"Value\": \"EC2-ALB-Target\"}]
      }
    ]
  }"
```

---

### Passo 5: Criar o Auto Scaling Group e Aplicar a Política de Escalonamento

```bash
# 1. Criar Auto Scaling Group com capacidade Min: 2, Desired: 2, Max: 4
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "asg-lab-web" \
  --launch-template "LaunchTemplateName=lt-lab-web,Version=\$Latest" \
  --min-size 2 \
  --max-size 4 \
  --desired-capacity 2 \
  --target-group-arns "$TG_ARN" \
  --vpc-zone-identifier "$SUBNET_A,$SUBNET_B" \
  --health-check-type ELB \
  --health-check-grace-period 180

# 2. Anexar Target Tracking Policy (50% de CPU)
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "asg-lab-web" \
  --policy-name "cpu50-target-tracking" \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration file://policies/asg-policy.json
```

---

## 🧪 Testes e Validação Prática

### 1. Validação de Balanceamento Round-Robin
Acesse o DNS do ALB no navegador ou via terminal para observar o chaveamento das Availability Zones e IDs de instância:

```bash
echo "Acesse a URL do Load Balancer:"
echo "http://$ALB_DNS"

# Teste com loop curl:
for i in {1..6}; do
  curl -s "http://$ALB_DNS" | grep -E "Availability Zone|Instance ID" | sed 's/<[^>]*>//g' | xargs
  sleep 1
done
```

*Saída esperada:* As respostas alternarão entre `us-east-1a` e `us-east-1b`, demonstrando balanceamento multi-AZ ativo.

---

### 2. Simulação de Alta Carga de CPU (Scale-Out)
Conecte-se a uma das instâncias ou execute o script de estresse localmente:

```bash
chmod +x scripts/stress_test.sh
./scripts/stress_test.sh 10
```

1. Acesse o **Amazon CloudWatch** > **Alarms**.
2. Observe o alarme de alta utilização de CPU (`TargetTracking-asg-lab-web-AlarmHigh-...`) entrar no estado **In ALARM**.
3. No painel do **Auto Scaling Groups**, observe a contagem de instâncias passar de 2 para 3 ou 4.
4. Após o encerramento do script, o alarme de baixa utilização fará o **Scale-In** gradual de volta para 2 instâncias.

---

## 💰 Estimativa de Custos

| Recurso AWS | Tipo / Configuração | Custo Estimado (Região us-east-1) |
| :--- | :--- | :--- |
| **EC2 (2x Instâncias)** | `t3.micro` (2 vCPU, 1 GB RAM) | Coberto pelo **AWS Free Tier** (750h/mês) ou ~$0.0104/hora |
| **Application Load Balancer** | 1 ALB ativo | ~$0.0225/hora (~$0.54/dia) + $0.008 por LCU consumida |
| **Target Group & Auto Scaling** | Gerenciamento | **Gratuito** |
| **CloudWatch Metrics básicas** | Intervalo padrão de 5 minutos | **Gratuito** |
| **Tráfego de Dados (Egress)** | Primeiros 100 GB/mês | **Gratuito** |

> 💡 **Dica de Custo:** Para fins de laboratório, execute os testes por 1 a 2 horas e execute o teardown logo em seguida para manter o custo total inferior a **US$ 0.10**.

---

## 🧹 Teardown / Limpeza de Recursos

Para evitar cobranças indesejadas na AWS, delete todos os recursos na ordem correta de dependência:

```bash
# 1. Reduzir capacidade do Auto Scaling Group para 0 e deletar
aws autoscaling update-auto-scaling-group --auto-scaling-group-name "asg-lab-web" --min-size 0 --desired-capacity 0
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "asg-lab-web" --force-delete

# 2. Deletar Launch Template
aws ec2 delete-launch-template --launch-template-name "lt-lab-web"

# 3. Deletar Application Load Balancer
aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"

# Aguardar finalização do ALB antes de remover o Target Group e Security Groups
sleep 30

# 4. Deletar Target Group
aws elbv2 delete-target-group --target-group-arn "$TG_ARN"

# 5. Deletar Security Groups
aws ec2 delete-security-group --group-id "$SG_EC2_ID"
aws ec2 delete-security-group --group-id "$SG_ALB_ID"

echo "[✓] Limpeza concluída com sucesso. Nenhum recurso faturável ativo."
```
