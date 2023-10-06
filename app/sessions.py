import uuid
import logging
from datetime import datetime
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

class Sessions:
    """
    Encapsulates an Amazon DynamoDB table of session data.
    """
    def __init__(self, dyn_resource):
        """
        :param dyn_resource: A Boto3 DynamoDB resource.
        """
        self.dyn_resource = dyn_resource
        self.table = None

    def exists(self, table_name):
        """
        Determines whether a table exists. As a side effect, stores the table in
        a member variable.

        :param table_name: The name of the table to check.
        :return: True when the table exists; otherwise, False.
        """
        try:
            table = self.dyn_resource.Table(table_name)
            table.load()
            exists = True
        except ClientError as err:
            if err.response['Error']['Code'] == 'ResourceNotFoundException':
                exists = False
            else:
                logger.error(
                    "Couldn't check for existence of %s. Here's why: %s: %s",
                    table_name,
                    err.response['Error']['Code'], err.response['Error']['Message'])
                raise
        else:
            self.table = table
        return exists

    def get_session(self, tenant_id):
        """
        Gets session data from the table for a specific session.

        :param tenantid: The Tenant ID
        :return: The data about the requested session.
        """
        try:
            response = self.table.get_item(Key={'TenantId': tenant_id})
        except ClientError as err:
            logger.error(
                "Couldn't get session %s from table %s. Here's why: %s: %s",
                tenant_id, self.table.name,
                err.response['Error']['Code'], err.response['Error']['Message'])
            raise
        else:
            if "Item" in response.keys():
                return response["Item"]

    def add_session(self, tenant_id):
        """
        Adds a session to the table.

        :param session_id: The current session_id for the tenant/user
        """
        session_id = str(uuid.uuid4())
        new_interaction = int(datetime.now().timestamp())
        try:
            self.table.put_item(
                Item={
                    'TenantId': tenant_id,
                    'session_id': session_id,
                    'last_interaction': new_interaction
                }
            )
        except ClientError as err:
            logger.error(
                "Couldn't add session %s to table %s. Here's why: %s: %s",
                session_id, self.table.name,
                err.response['Error']['Code'], err.response['Error']['Message'])
            raise

    def update_session_last_interaction(self, tenant_id, new_interaction):
        """
        Updates last_interaction data for a session in the table.

        :param tenant_id: The tenant_id of the session to update.
        :param last_interaction: The last_interaction time of the session to update.
        :return: The fields that were updated, with their new values.
        """
        try:
            response = self.table.update_item(
                Key={'TenantId': tenant_id},
                UpdateExpression="set last_interaction=:new_interaction",
                ExpressionAttributeValues={':new_interaction': new_interaction},
                ReturnValues="UPDATED_NEW")
        except ClientError as err:
            logger.error(
                "Couldn't update session %s in table %s. Here's why: %s: %s",
                tenant_id, self.table.name,
                err.response['Error']['Code'], err.response['Error']['Message'])
            raise
        else:
            return response['Attributes']

    def update_session(self, tenant_id, new_interaction):
        """
        Updates session_id and last_interaction data for a session in the table.

        :param tenant_id: The tenant_id of the session to update.
        :param last_interaction: The last_interaction time of the session to update.
        :return: The fields that were updated, with their new values.
        """
        session_id = str(uuid.uuid4())

        try:
            response = self.table.update_item(
                Key={'TenantId': tenant_id},
                UpdateExpression="set session_id=:session_id, last_interaction=:new_interaction",
                ExpressionAttributeValues={':session_id': session_id, 
                    ':new_interaction': new_interaction},
                ReturnValues="UPDATED_NEW")
        except ClientError as err:
            logger.error(
                "Couldn't update session %s in table %s. Here's why: %s: %s",
                tenant_id, self.table.name,
                err.response['Error']['Code'], err.response['Error']['Message'])
            raise
        else:
            return response['Attributes']