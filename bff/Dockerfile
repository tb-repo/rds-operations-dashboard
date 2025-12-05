# Dockerfile for Express BFF Lambda Container
# 
# This Dockerfile packages the Express BFF application for deployment as a Lambda container.
# It uses the AWS Lambda Node.js 18 base image which includes the Lambda Runtime Interface Client.
#
# Metadata:
# {
#   "generated_by": "claude-3.5-sonnet",
#   "timestamp": "2025-12-01T10:30:00Z",
#   "version": "1.0.0",
#   "policy_version": "v1.0.0",
#   "traceability": "REQ-1.1, REQ-1.4 → DESIGN-BFF-Container → TASK-1.1",
#   "review_status": "Pending",
#   "risk_level": "Level 2",
#   "reviewed_by": null,
#   "approved_by": null
# }

FROM public.ecr.aws/lambda/nodejs:18

# Set working directory
WORKDIR ${LAMBDA_TASK_ROOT}

# Copy package files
COPY package*.json ./

# Install production dependencies only
# Use npm ci for faster, more reliable installs
RUN npm ci --only=production

# Copy TypeScript configuration
COPY tsconfig.json ./

# Copy source code
COPY src ./src

# Install TypeScript and build dependencies temporarily
RUN npm install --save-dev typescript @types/node && \
    npm run build && \
    npm uninstall typescript @types/node

# Copy built JavaScript files to root (Lambda expects handler at root level)
RUN cp -r dist/* ./

# Install AWS Lambda Web Adapter for Express compatibility
# This allows Express to run in Lambda without code changes
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.7.1 /lambda-adapter /opt/extensions/lambda-adapter

# Set environment variables for Lambda Web Adapter
ENV PORT=8080
ENV AWS_LWA_INVOKE_MODE=response_stream
ENV AWS_LWA_READINESS_CHECK_PATH=/health
ENV AWS_LWA_READINESS_CHECK_PORT=8080

# The CMD is the command that Lambda will execute
# For Express with Lambda Web Adapter, we start the Express server
CMD ["node", "index.js"]
