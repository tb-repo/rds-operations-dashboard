/**
 * Lambda Handler for BFF using @vendia/serverless-express
 * 
 * This file wraps the Express application for AWS Lambda execution.
 * It uses serverless-express to handle the conversion between Lambda events
 * and Express HTTP requests/responses.
 */

import serverlessExpress from '@vendia/serverless-express';
import app from './index';

// Create the serverless Express handler
// This will handle all Lambda invocations and route them to the Express app
export const handler = serverlessExpress({ app });
