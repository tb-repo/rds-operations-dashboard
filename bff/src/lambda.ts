/**
 * AWS Lambda Handler for BFF Express Application
 * 
 * This file wraps the Express app for Lambda execution using serverless-express.
 * The Lambda function handler is exported as 'handler'.
 */

import serverlessExpress from '@vendia/serverless-express'
import app from './index'

// Create Lambda handler by wrapping Express app
export const handler = serverlessExpress({ app })
