import { Router, Request, Response } from 'express'
import { CognitoAdminService } from '../services/cognito-admin'
import { auditService } from '../services/audit'
import { logger } from '../utils/logger'

export function createUserRoutes(cognitoAdminService: CognitoAdminService): Router {
  const router = Router()

  /**
   * GET /api/users - List all users
   * Permission: manage_users
   */
  router.get('/', async (req: Request, res: Response) => {
    try {
      const limit = parseInt(req.query.limit as string) || 60
      const paginationToken = req.query.paginationToken as string | undefined

      const result = await cognitoAdminService.listUsers(limit, paginationToken)

      // Fetch groups for each user
      const usersWithGroups = await Promise.all(
        result.users.map(async (user) => {
          const groups = await cognitoAdminService.getUserGroups(user.id)
          return { ...user, groups }
        })
      )

      res.json({
        users: usersWithGroups,
        total: usersWithGroups.length,
        nextToken: result.nextToken,
      })
    } catch (error) {
      logger.error('Error listing users', {
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      res.status(500).json({
        error: 'Internal Server Error',
        message: 'Failed to list users',
      })
    }
  })

  /**
   * GET /api/users/me - Get current user profile
   * No specific permission required (authenticated users only)
   */
  router.get('/me', async (req: Request, res: Response) => {
    if (!req.user) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Authentication required',
      })
    }

    try {
      const userDetails = await cognitoAdminService.getUserDetails(req.user.userId)

      if (!userDetails) {
        return res.status(404).json({
          error: 'Not Found',
          message: 'User not found',
        })
      }

      res.json(userDetails)
    } catch (error) {
      logger.error('Error getting current user', {
        userId: req.user.userId,
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      res.status(500).json({
        error: 'Internal Server Error',
        message: 'Failed to get user details',
      })
    }
  })

  /**
   * GET /api/users/:userId - Get specific user details
   * Permission: manage_users
   */
  router.get('/:userId', async (req: Request, res: Response) => {
    try {
      const userDetails = await cognitoAdminService.getUserDetails(req.params.userId)

      if (!userDetails) {
        return res.status(404).json({
          error: 'Not Found',
          message: 'User not found',
        })
      }

      res.json(userDetails)
    } catch (error) {
      logger.error('Error getting user details', {
        userId: req.params.userId,
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      res.status(500).json({
        error: 'Internal Server Error',
        message: 'Failed to get user details',
      })
    }
  })

  /**
   * POST /api/users/:userId/groups - Add user to group (assign role)
   * Permission: manage_users
   */
  router.post('/:userId/groups', async (req: Request, res: Response) => {
    try {
      const { group } = req.body

      if (!group) {
        return res.status(400).json({
          error: 'Bad Request',
          message: 'Group name is required',
        })
      }

      // Validate group name
      const validGroups = ['Admin', 'DBA', 'ReadOnly']
      if (!validGroups.includes(group)) {
        return res.status(400).json({
          error: 'Bad Request',
          message: `Invalid group. Must be one of: ${validGroups.join(', ')}`,
        })
      }

      // Get target user details
      const targetUser = await cognitoAdminService.getUserDetails(req.params.userId)
      if (!targetUser) {
        return res.status(404).json({
          error: 'Not Found',
          message: 'User not found',
        })
      }

      // Add user to group
      await cognitoAdminService.addUserToGroup(req.params.userId, group)

      // Log the role change
      auditService.logUserRoleChange(
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.params.userId,
        targetUser.email,
        'add_role',
        group,
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        'success'
      )

      res.json({
        message: 'User added to group successfully',
        userId: req.params.userId,
        group,
      })
    } catch (error) {
      logger.error('Error adding user to group', {
        userId: req.params.userId,
        error: error instanceof Error ? error.message : 'Unknown error',
      })

      // Log failed role change
      if (req.user) {
        auditService.logUserRoleChange(
          req.user.userId,
          req.user.email,
          req.params.userId,
          'unknown',
          'add_role',
          req.body.group || 'unknown',
          req.ip || 'unknown',
          req.get('user-agent') || 'unknown',
          'failure',
          undefined,
          { error: error instanceof Error ? error.message : 'Unknown error' }
        )
      }

      res.status(500).json({
        error: 'Internal Server Error',
        message: error instanceof Error ? error.message : 'Failed to add user to group',
      })
    }
  })

  /**
   * DELETE /api/users/:userId/groups/:groupName - Remove user from group (revoke role)
   * Permission: manage_users
   */
  router.delete('/:userId/groups/:groupName', async (req: Request, res: Response) => {
    try {
      const { userId, groupName } = req.params

      // Validate group name
      const validGroups = ['Admin', 'DBA', 'ReadOnly']
      if (!validGroups.includes(groupName)) {
        return res.status(400).json({
          error: 'Bad Request',
          message: `Invalid group. Must be one of: ${validGroups.join(', ')}`,
        })
      }

      // Get target user details
      const targetUser = await cognitoAdminService.getUserDetails(userId)
      if (!targetUser) {
        return res.status(404).json({
          error: 'Not Found',
          message: 'User not found',
        })
      }

      // Remove user from group
      await cognitoAdminService.removeUserFromGroup(userId, groupName)

      // Log the role change
      auditService.logUserRoleChange(
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        userId,
        targetUser.email,
        'remove_role',
        groupName,
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        'success'
      )

      res.json({
        message: 'User removed from group successfully',
        userId,
        group: groupName,
      })
    } catch (error) {
      logger.error('Error removing user from group', {
        userId: req.params.userId,
        groupName: req.params.groupName,
        error: error instanceof Error ? error.message : 'Unknown error',
      })

      // Log failed role change
      if (req.user) {
        auditService.logUserRoleChange(
          req.user.userId,
          req.user.email,
          req.params.userId,
          'unknown',
          'remove_role',
          req.params.groupName,
          req.ip || 'unknown',
          req.get('user-agent') || 'unknown',
          'failure',
          undefined,
          { error: error instanceof Error ? error.message : 'Unknown error' }
        )
      }

      res.status(500).json({
        error: 'Internal Server Error',
        message: error instanceof Error ? error.message : 'Failed to remove user from group',
      })
    }
  })

  return router
}
