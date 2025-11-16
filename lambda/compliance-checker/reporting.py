#!/usr/bin/env python3
"""
Compliance Reporter

Generates compliance reports and saves them to S3.
"""

import os
import sys
import json
from datetime import datetime
from typing import Dict, List, Any

sys.path.append(os.path.join(os.path.dirname(__file__), '..'))
from shared.logger import get_logger
from shared.aws_clients import get_s3_client

logger = get_logger(__name__)


class ComplianceReporter:
    """Generate and save compliance reports."""
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize compliance reporter.
        
        Args:
            config: Configuration dict
        """
        self.config = config
        self.s3 = get_s3_client()
    
    def generate_compliance_report(
        self,
        instances: List[Dict[str, Any]],
        violations: List[Dict[str, Any]],
        compliant_count: int
    ) -> Dict[str, Any]:
        """
        Generate comprehensive compliance report.
        
        Args:
            instances: List of RDS instances
            violations: List of compliance violations
            compliant_count: Number of compliant instances
            
        Returns:
            dict: Complete compliance report
        """
        report_date = datetime.utcnow().strftime('%Y-%m-%d')
        
        # Group violations by severity
        violations_by_severity = {
            'critical': [v for v in violations if v['severity'] == 'Critical'],
            'high': [v for v in violations if v['severity'] == 'High'],
            'medium': [v for v in violations if v['severity'] == 'Medium'],
            'low': [v for v in violations if v['severity'] == 'Low']
        }
        
        # Group violations by check type
        violations_by_type = {}
        for v in violations:
            check_type = v['check_type']
            if check_type not in violations_by_type:
                violations_by_type[check_type] = []
            violations_by_type[check_type].append(v)
        
        # Group violations by instance
        violations_by_instance = {}
        for v in violations:
            instance_id = v['instance_id']
            if instance_id not in violations_by_instance:
                violations_by_instance[instance_id] = []
            violations_by_instance[instance_id].append(v)
        
        report = {
            'report_date': report_date,
            'generated_at': datetime.utcnow().isoformat() + 'Z',
            'summary': {
                'total_instances': len(instances),
                'compliant_instances': compliant_count,
                'non_compliant_instances': len(instances) - compliant_count,
                'compliance_rate': round((compliant_count / len(instances) * 100) if instances else 0, 1),
                'total_violations': len(violations),
                'critical_violations': len(violations_by_severity['critical']),
                'high_violations': len(violations_by_severity['high']),
                'medium_violations': len(violations_by_severity['medium']),
                'low_violations': len(violations_by_severity['low'])
            },
            'violations_by_severity': {
                'critical': violations_by_severity['critical'],
                'high': violations_by_severity['high'],
                'medium': violations_by_severity['medium'],
                'low': violations_by_severity['low']
            },
            'violations_by_type': {
                k: len(v) for k, v in violations_by_type.items()
            },
            'violations_by_instance': {
                k: len(v) for k, v in violations_by_instance.items()
            },
            'detailed_violations': violations,
            'remediation_summary': self._generate_remediation_summary(violations)
        }
        
        logger.info(f"Generated compliance report: {compliant_count}/{len(instances)} compliant, {len(violations)} violations")
        
        return report
    
    def save_report_to_s3(self, report: Dict[str, Any]) -> str:
        """
        Save compliance report to S3.
        
        Args:
            report: Compliance report data
            
        Returns:
            str: S3 key where report was saved
        """
        bucket_name = self.config.get('s3_bucket', 'rds-dashboard-data')
        report_date = report['report_date']
        year, month, day = report_date.split('-')
        
        # S3 key: compliance-reports/YYYY/MM/compliance_report_YYYY-MM-DD.json
        s3_key = f"compliance-reports/{year}/{month}/compliance_report_{report_date}.json"
        
        try:
            report_json = json.dumps(report, indent=2, default=str)
            
            self.s3.put_object(
                Bucket=bucket_name,
                Key=s3_key,
                Body=report_json.encode('utf-8'),
                ContentType='application/json',
                ServerSideEncryption='AES256',
                Metadata={
                    'report-date': report_date,
                    'generated-by': 'compliance-checker',
                    'version': '1.0.0'
                }
            )
            
            logger.info(f"Saved compliance report to s3://{bucket_name}/{s3_key}")
            return s3_key
            
        except Exception as e:
            logger.error(f"Failed to save report to S3: {str(e)}")
            raise
    
    def _generate_remediation_summary(self, violations: List[Dict[str, Any]]) -> Dict[str, List[str]]:
        """
        Generate summary of remediation actions by check type.
        
        Args:
            violations: List of violations
            
        Returns:
            dict: Remediation actions grouped by check type
        """
        remediation_by_type = {}
        
        for violation in violations:
            check_type = violation['check_type']
            remediation = violation.get('remediation', 'No remediation available')
            
            if check_type not in remediation_by_type:
                remediation_by_type[check_type] = set()
            
            remediation_by_type[check_type].add(remediation)
        
        # Convert sets to lists
        return {k: list(v) for k, v in remediation_by_type.items()}
