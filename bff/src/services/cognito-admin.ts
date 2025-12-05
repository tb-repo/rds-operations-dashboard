import {
  CognitoIdentityProviderClient,
  ListUsersCommand,
  AdminGetUserCommand,
  AdminAddUserToGroupCommand,
  AdminRemoveUserFromGroupCommand,
  AdminListGroupsForUserCommand,
  ListUsersCommandOutput,
  AdminGetUserCommandOutput,
  AdminListGroupsForUserCommandOutput,
} from '@aws-sdk/client-cognito-identity-provider'
import { logger } from '../utils/logger'

export interface UserInfo {
  id: string
  email: string
  name?: string
  groups: string[]
  status: string
  createdAt: string
  lastLogin?: string
  attributes: Record<string, string>
}

export interface ListUsersResult {
  users: UserInfo[]
  total: number
  nextToken?: string
}

export class CognitoAdminService {
  private client: CognitoIdentityProviderClient
  private userPoolId: string

  constructor(region: string, userPoolId: string) {
    this.client = new CognitoIdentityProviderClient({ region })
    this.userPoolId = userPoolId
    logger.info('Cognito admin service initialized', { userPoolId })
  }

  /**
   * List all users in the user pool
   */
  async listUsers(limit: number = 60, paginationToken?: string): Promise<ListUsersResult> {
    try {
      const command = new ListUsersCommand({
        UserPoolId: this.userPoolId,
        Limit: limit,
        PaginationToken: paginationToken,
      })

      const response: ListUsersCommandOutput = await this.client.send(command)

      const users: UserInfo[] = (response.Users || []).map(user => this.mapCognitoUser(user))

      return {
        users,
        total: users.length,
        nextToken: response.PaginationToken,
      }
    } catch (error) {
      logger.error('Error listing users', {
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      throw new Error('Failed to list users')
    }
  }

  /**
   * Get details for a specific user
   */
  async getUserDetails(username: string): Promise<UserInfo | null> {
    try {
      const command = new AdminGetUserCommand({
        UserPoolId: this.userPoolId,
        Username: username,
      })

      const response: AdminGetUserCommandOutput = await this.client.send(command)

      // Get user groups
      const groups = await this.getUserGroups(username)

      return {
        id: response.Username || username,
        email: this.getAttributeValue(response.UserAttributes, 'email') || '',
        name: this.getAttributeValue(response.UserAttributes, 'name'),
        groups,
        status: response.UserStatus || 'UNKNOWN',
        createdAt: response.UserCreateDate?.toISOString() || '',
        lastLogin: response.UserLastModifiedDate?.toISOString(),
        attributes: this.mapAttributes(response.UserAttributes),
      }
    } catch (error) {
      logger.error('Error getting user details', {
        username,
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      return null
    }
  }

  /**
   * Get groups for a user
   */
  async getUserGroups(username: string): Promise<string[]> {
    try {
      const command = new AdminListGroupsForUserCommand({
        UserPoolId: this.userPoolId,
        Username: username,
      })

      const response: AdminListGroupsForUserCommandOutput = await this.client.send(command)

      return (response.Groups || []).map(group => group.GroupName || '').filter(name => name)
    } catch (error) {
      logger.error('Error getting user groups', {
        username,
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      return []
    }
  }

  /**
   * Add user to a group (assign role)
   */
  async addUserToGroup(username: string, groupName: string): Promise<boolean> {
    try {
      const command = new AdminAddUserToGroupCommand({
        UserPoolId: this.userPoolId,
        Username: username,
        GroupName: groupName,
      })

      await this.client.send(command)

      logger.info('User added to group', { username, groupName })
      return true
    } catch (error) {
      logger.error('Error adding user to group', {
        username,
        groupName,
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      throw new Error(`Failed to add user to group: ${error instanceof Error ? error.message : 'Unknown error'}`)
    }
  }

  /**
   * Remove user from a group (revoke role)
   */
  async removeUserFromGroup(username: string, groupName: string): Promise<boolean> {
    try {
      const command = new AdminRemoveUserFromGroupCommand({
        UserPoolId: this.userPoolId,
        Username: username,
        GroupName: groupName,
      })

      await this.client.send(command)

      logger.info('User removed from group', { username, groupName })
      return true
    } catch (error) {
      logger.error('Error removing user from group', {
        username,
        groupName,
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      throw new Error(`Failed to remove user from group: ${error instanceof Error ? error.message : 'Unknown error'}`)
    }
  }

  /**
   * Map Cognito user to UserInfo
   */
  private mapCognitoUser(cognitoUser: any): UserInfo {
    return {
      id: cognitoUser.Username || '',
      email: this.getAttributeValue(cognitoUser.Attributes, 'email') || '',
      name: this.getAttributeValue(cognitoUser.Attributes, 'name'),
      groups: [], // Will be populated separately if needed
      status: cognitoUser.UserStatus || 'UNKNOWN',
      createdAt: cognitoUser.UserCreateDate?.toISOString() || '',
      lastLogin: cognitoUser.UserLastModifiedDate?.toISOString(),
      attributes: this.mapAttributes(cognitoUser.Attributes),
    }
  }

  /**
   * Get attribute value from Cognito attributes array
   */
  private getAttributeValue(attributes: any[] | undefined, name: string): string | undefined {
    if (!attributes) return undefined
    const attr = attributes.find(a => a.Name === name)
    return attr?.Value
  }

  /**
   * Map Cognito attributes to key-value object
   */
  private mapAttributes(attributes: any[] | undefined): Record<string, string> {
    if (!attributes) return {}
    
    const mapped: Record<string, string> = {}
    for (const attr of attributes) {
      if (attr.Name && attr.Value) {
        mapped[attr.Name] = attr.Value
      }
    }
    return mapped
  }
}
