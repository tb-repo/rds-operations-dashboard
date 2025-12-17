# Dockerfile for Express BFF Lambda Container
# 
# This Dockerfile packages the Express BFF application for deployment as a Lambda container.
# It uses the AWS Lambda Node.js 18 base image and @vendia/serverless-express for Lambda integration.
#
# Metadata:
# {
#   "generated_by": "claude-3.5-sonnet",
#   "timestamp": "2025-12-07T10:00:00Z",
#   "version": "2.0.0",
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

# The CMD specifies the Lambda handler
# Format: filename.exportedHandlerFunction
# This points to the handler exported from lambda.ts
CMD ["lambda.handler"]
